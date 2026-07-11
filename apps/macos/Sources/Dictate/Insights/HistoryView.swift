import SwiftUI
import AppKit

/// The searchable, per-app-filterable feed of every dictation. Search + filter live in the window
/// toolbar (InsightsWindow) and land here through InsightsNav; the opened item is plain local state —
/// no NavigationStack, matching this window's fixed-layout philosophy. Tap a row to open it: replay
/// the saved recording, fix the text, and teach the dictionary.
struct HistoryView: View {
    @ObservedObject var store: InsightStore
    @ObservedObject var nav: InsightsNav
    @State private var opened: DictationEvent? = nil
    @FocusState private var focusedEvent: String?

    private var rows: [DictationEvent] {
        store.events.reversed().filter(matches)
    }
    private func matches(_ e: DictationEvent) -> Bool {
        if let f = nav.historyAppFilter, (e.appBundleId ?? e.appName ?? "Unknown") != f { return false }
        if nav.historySearch.isEmpty { return true }
        return e.text.localizedCaseInsensitiveContains(nav.historySearch)
            || (e.appName ?? "").localizedCaseInsensitiveContains(nav.historySearch)
    }

    var body: some View {
        Group {
            if let e = opened {
                DictationDetailView(store: store, event: e, onClose: { opened = nil })
                    .transition(.opacity)
            } else {
                feed
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: opened)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
    }

    @ViewBuilder private var feed: some View {
        if store.events.isEmpty {
            EmptyState(title: "No dictations yet",
                       hint: "Hold Fn and speak — every dictation lands here with its recording.")
        } else if rows.isEmpty {
            // Filtered to nothing — say so plainly, so it doesn't read as lost history.
            Text("No matches.")
                .font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Full-bleed rows on the window background, inset hairlines between — no List chrome.
            ScrollView {
                LazyVStack(spacing: 0) {
                    let list = rows
                    ForEach(list) { e in
                        HistoryRowButton(store: store, event: e,
                                         focused: focusedEvent == e.id) { opened = e }
                            .focused($focusedEvent, equals: e.id)
                        if e.id != list.last?.id {
                            // Inset both ends to the text column so the hairline sits on the page grid.
                            Hairline().padding(.leading, 76).padding(.trailing, 8)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
    }
}

/// One tappable feed row: a real Button (Return/Space open it when focused). Hover is a subtle ink
/// fill — no second hue — and keyboard focus draws the same 2px electric-bright (crest) ring as
/// FilledButton/GhostButton.
private struct HistoryRowButton: View {
    @ObservedObject var store: InsightStore
    let event: DictationEvent
    let focused: Bool
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            HistoryRow(store: store, event: event)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovered ? WarbleTheme.ink : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(WarbleTheme.electricBright, lineWidth: 2)
            .padding(-2)
            .opacity(focused ? 1 : 0))
        .onHover { hovered = $0 }
    }
}

/// Row anatomy shared with Home's feed: time gutter, two-line text, app + counts metadata, and a
/// small trailing glyph saying what's replayable (waveform = saved audio, speaker = read-aloud).
struct HistoryRow: View {
    @ObservedObject var store: InsightStore
    let event: DictationEvent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(RowTime.string(event.date))
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(WarbleTheme.mist)
                .frame(width: 56, alignment: .trailing)
                .padding(.top, 2) // optical align with the 13pt first line
            VStack(alignment: .leading, spacing: 3) {
                Text(event.isFailed ? "transcription failed — recording kept"
                     : event.text.isEmpty ? "\(event.words) words" : event.text)
                    .font(.system(size: 13))
                    .foregroundStyle(event.isFailed ? WarbleTheme.mist : WarbleTheme.textHi)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    if let app = event.appName {
                        Text(app).foregroundStyle(WarbleTheme.electricText)
                    }
                    Text(meta).foregroundStyle(WarbleTheme.mist)
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
            // Failure is warn + a glyph (never color alone); otherwise the glyph says what's replayable.
            Image(systemName: event.isFailed ? "exclamationmark.triangle"
                  : event.kind == "read" ? "speaker.wave.2.fill"
                  : (store.audioURL(for: event) != nil ? "waveform" : "mic.fill"))
                .font(.system(size: 12))
                .foregroundStyle(event.isFailed ? WarbleTheme.warn : WarbleTheme.mist)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
    private var meta: String {
        if event.isFailed { return "· open to re-transcribe" }
        if event.kind == "read" { return "· \(event.words) words" }
        return "· \(event.words) words · \(event.wpm) wpm"
    }
}

/// The opened dictation: replay, correct the text, and teach the dictionary. Presented by
/// HistoryView's explicit `opened` state; `onClose` is the only way back (no dismiss environment).
struct DictationDetailView: View {
    @ObservedObject var store: InsightStore
    let event: DictationEvent
    let onClose: () -> Void
    @StateObject private var audio = AudioPlayer()
    @State private var editedText: String
    @State private var heard = ""
    @State private var correct = ""
    @State private var note = ""
    @State private var backHovered = false
    @State private var deleteHovered = false
    @State private var rawShown = false
    @State private var rawHovered = false
    @State private var retranscribing = false
    @State private var recoverNote = ""

    init(store: InsightStore, event: DictationEvent, onClose: @escaping () -> Void) {
        self.store = store
        self.event = event
        self.onClose = onClose
        _editedText = State(initialValue: event.text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button { onClose() } label: {
                    Label("History", systemImage: "chevron.left")
                        .font(.system(size: 13))
                        .foregroundStyle(backHovered ? WarbleTheme.textHi : WarbleTheme.mist)
                }
                .buttonStyle(.plain)
                .onHover { backHovered = $0 }

                HStack(spacing: 12) {
                    AppIconView(bundleId: event.appBundleId, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.appName ?? (event.kind == "read" ? "Read aloud" : "Dictation"))
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
                        Text(metaLine).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                    }
                    Spacer()
                }

                // The replay strip sits directly on the background — the play glyph is the affordance.
                if let url = store.audioURL(for: event) {
                    HStack(spacing: 12) {
                        Button { audio.toggle(url) } label: {
                            Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28)).foregroundStyle(WarbleTheme.electric)
                        }
                        .buttonStyle(.plain)
                        ProgressView(value: audio.progress).tint(WarbleTheme.electric)
                        Text("recording").font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                    }
                } else if event.kind == "dictate" {
                    Text("No saved recording for this one.").font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                }

                // A FAILED dictation: the words aren't transcribed yet, but the recording is kept.
                // Re-transcribe runs the normal pipeline again and resolves this item in place —
                // History only, never a paste. Warn + glyph per the failure styling (DESIGN.md).
                if current.isFailed {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(WarbleTheme.warn)
                        Text("transcription failed — the recording is kept")
                            .font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
                        Spacer()
                        Button(retranscribing ? "Re-transcribing…" : "Re-transcribe") { retranscribe() }
                            .disabled(retranscribing || store.audioURL(for: current) == nil)
                    }
                    if !recoverNote.isEmpty {
                        Text(recoverNote).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                    }
                }

                SectionHeader(title: "Transcript").padding(.top, 8)
                // The editor keeps a border — it's a real text field, the one place a box is earned.
                TextEditor(text: $editedText)
                    .font(.system(size: 14))
                    .foregroundStyle(WarbleTheme.textHi)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(WarbleTheme.ink, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WarbleTheme.line, lineWidth: 1))
                HStack {
                    Spacer()
                    Button("Save text") { store.updateText(event.id, to: editedText); note = "Saved." }
                        .disabled(editedText == current.text)
                }

                // Undo-polish: the verbatim transcript, one quiet disclosure away (product.md §4 —
                // anything that rewrites must be undoable to the raw words). Mist text, no box.
                if let raw = current.raw {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { rawShown.toggle() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .rotationEffect(.degrees(rawShown ? 90 : 0))
                                Text("what you actually said")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(rawHovered ? WarbleTheme.textHi : WarbleTheme.mist)
                        }
                        .buttonStyle(.plain)
                        .onHover { rawHovered = $0 }
                        if rawShown {
                            Text(raw)
                                .font(.system(size: 13))
                                .foregroundStyle(WarbleTheme.mist)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { editedText = raw } label: {
                                Text("use this as the transcript")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WarbleTheme.electricText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                SectionHeader(title: "Teach the dictionary").padding(.top, 8)
                Text("Heard a word wrong? Add the fix so future dictations get it right — that's how you train it.")
                    .font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                HStack(spacing: 8) {
                    TextField("warble heard…", text: $heard).textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundStyle(WarbleTheme.mist)
                    TextField("should be…", text: $correct).textFieldStyle(.roundedBorder)
                    Button("Add") { addCorrection() }.disabled(heard.isEmpty || correct.isEmpty)
                }
                if !note.isEmpty {
                    Text(note).font(.system(size: 11)).foregroundStyle(WarbleTheme.electricText)
                }

                Hairline().padding(.top, 8)
                // Destructive stays neutral (One-Accent Rule: no red) — the trash glyph carries the
                // meaning, hover brightens mist to text-hi, same as every ghost affordance.
                Button(role: .destructive) {
                    audio.stop(); store.delete(event); onClose()
                } label: {
                    Label("Delete this dictation", systemImage: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(deleteHovered ? WarbleTheme.textHi : WarbleTheme.mist)
                }
                .buttonStyle(.plain)
                .onHover { deleteHovered = $0 }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
        .onDisappear { audio.stop() }
    }

    /// Run the normal pipeline over the kept recording; success resolves the FAILED mark in place
    /// and fills the transcript editor. Never pastes anywhere.
    private func retranscribe() {
        retranscribing = true
        recoverNote = ""
        Recovery.retranscribe(current) { outcome in
            retranscribing = false
            switch outcome {
            case .text(let cleaned, _):
                editedText = cleaned
                recoverNote = "Recovered."
            case .silence:
                recoverNote = "Nothing heard in this recording."
            case .failed:
                recoverNote = "Still failing — every engine errored. The recording stays."
            }
        }
    }

    private func addCorrection() {
        let from = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }
        Lexicon.shared.learnExplicit(from: from, to: to)
        note = "Added “\(from)” → “\(to)” to your dictionary."
        heard = ""; correct = ""
    }

    /// The live event from the store, so the header + Save button reflect an edit immediately
    /// (the captured `event` value is frozen at open time).
    private var current: DictationEvent { store.events.first { $0.id == event.id } ?? event }

    private var metaLine: String {
        if current.isFailed {
            let secs = String(format: "%.0f", Double(current.durationMs) / 1000)
            return "\(RelTime.string(current.date)) · failed · \(secs)s recording · \(current.engine)"
        }
        if current.kind == "read" {
            return "\(RelTime.string(current.date)) · read aloud · \(current.words) words · \(current.engine)"
        }
        return "\(RelTime.string(current.date)) · \(current.words) words · \(current.wpm) wpm · \(current.engine)"
    }
}

/// Small app icon resolved from a bundle id (falls back to a glyph once the app has quit).
struct AppIconView: View {
    let bundleId: String?
    var size: CGFloat = 22
    var body: some View {
        if let img = Self.icon(bundleId) {
            Image(nsImage: img).resizable().frame(width: size, height: size).cornerRadius(size * 0.22)
        } else {
            Image(systemName: "app.dashed").font(.system(size: size * 0.8))
                .foregroundStyle(WarbleTheme.mist).frame(width: size, height: size)
        }
    }
    static func icon(_ bundleId: String?) -> NSImage? {
        guard let b = bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum RelTime {
    private static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()
    static func string(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? time.string(from: date) : rel.localizedString(for: date, relativeTo: Date())
    }
}
