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
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "History",
                       subtitle: "Every dictation and read-aloud, newest first — open one to replay or fix it.")
                .padding(.horizontal, 28).padding(.top, 28)
            if store.events.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", title: "No dictations yet",
                           message: "Hold Fn and speak. Every dictation lands here with its recording, so you can replay it or fix a word.")
            } else if rows.isEmpty {
                // Filtered to nothing — say so plainly, so it doesn't read as lost history.
                Text("No matches.")
                    .font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(rows) { e in
                        HistoryRowButton(store: store, event: e,
                                         focused: focusedEvent == e.id) { opened = e }
                            .focused($focusedEvent, equals: e.id)
                            .listRowBackground(WarbleTheme.ink)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(WarbleTheme.black)
            }
        }
    }
}

/// One tappable feed row: a real Button (Return/Space open it when focused). Hover is a neutral
/// lift drawn inside the row — no second hue — and keyboard focus draws the same 2px
/// electric-bright (crest) ring as FilledButton/GhostButton.
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
        .background(hovered ? Color.white.opacity(0.04) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(WarbleTheme.electricBright, lineWidth: 2)
            .padding(-2)
            .opacity(focused ? 1 : 0))
        .onHover { hovered = $0 }
    }
}

struct HistoryRow: View {
    @ObservedObject var store: InsightStore
    let event: DictationEvent
    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundleId: event.appBundleId)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.text.isEmpty ? "\(event.words) words" : event.text)
                    .font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi).lineLimit(1)
                HStack(spacing: 6) {
                    Text(event.appName ?? "—").foregroundStyle(WarbleTheme.electricText)
                    Text("· \(RelTime.string(event.date)) · \(event.words) words").foregroundStyle(WarbleTheme.mist)
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
            Image(systemName: event.kind == "read" ? "speaker.wave.2.fill"
                                                    : (store.audioURL(for: event) != nil ? "waveform" : "mic.fill"))
                .font(.system(size: 12)).foregroundStyle(WarbleTheme.mist)
        }
        .padding(.vertical, 4)
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

    init(store: InsightStore, event: DictationEvent, onClose: @escaping () -> Void) {
        self.store = store
        self.event = event
        self.onClose = onClose
        _editedText = State(initialValue: event.text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
                        Text(metaLine).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                    }
                    Spacer()
                }

                if let url = store.audioURL(for: event) {
                    HStack(spacing: 12) {
                        Button { audio.toggle(url) } label: {
                            Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 30)).foregroundStyle(WarbleTheme.electric)
                        }
                        .buttonStyle(.plain)
                        ProgressView(value: audio.progress).tint(WarbleTheme.electric)
                        Text("recording").font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                    }
                    .padding(12)
                    .background(WarbleTheme.ink, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WarbleTheme.line, lineWidth: 1))
                } else if event.kind == "dictate" {
                    Text("No saved recording for this one.").font(.system(size: 12)).foregroundStyle(WarbleTheme.mist)
                }

                section("Transcript")
                TextEditor(text: $editedText)
                    .font(.system(size: 14))
                    .foregroundStyle(WarbleTheme.textHi)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(WarbleTheme.ink, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WarbleTheme.line, lineWidth: 1))
                HStack {
                    Spacer()
                    Button("Save text") { store.updateText(event.id, to: editedText); note = "Saved." }
                        .disabled(editedText == current.text)
                }

                section("Teach the dictionary")
                Text("Heard a word wrong? Add the fix so future dictations get it right — that's how you train it.")
                    .font(.system(size: 12)).foregroundStyle(WarbleTheme.mist)
                HStack(spacing: 8) {
                    TextField("warble heard…", text: $heard).textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundStyle(WarbleTheme.mist)
                    TextField("should be…", text: $correct).textFieldStyle(.roundedBorder)
                    Button("Add") { addCorrection() }.disabled(heard.isEmpty || correct.isEmpty)
                }
                if !note.isEmpty {
                    Text(note).font(.system(size: 12)).foregroundStyle(WarbleTheme.electricText)
                }

                Divider().overlay(WarbleTheme.line).padding(.top, 8)
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
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
        .onDisappear { audio.stop() }
    }

    private func addCorrection() {
        let from = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }
        Lexicon.shared.learnExplicit(from: from, to: to)
        note = "Added “\(from)” → “\(to)” to your dictionary."
        heard = ""; correct = ""
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(WarbleTheme.mist).textCase(.uppercase)
    }

    /// The live event from the store, so the header + Save button reflect an edit immediately
    /// (the captured `event` value is frozen at open time).
    private var current: DictationEvent { store.events.first { $0.id == event.id } ?? event }

    private var metaLine: String {
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
