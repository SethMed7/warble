import SwiftUI
import AppKit

/// The dictionary, ported into the dashboard: spelling corrections (dictation), pronunciations
/// (read-aloud), the learning candidates, the promote-threshold, and the file location. Wired through
/// the same Lexicon the rest of the app uses; Lexicon has no publisher, so we reload after each edit.
/// Sections sit directly on the background — 13pt headers, hairline-divided rows, no boxes.
struct DictionaryView: View {
    struct Pair: Identifiable { let id = UUID(); let a: String; let b: String }
    struct Pend: Identifiable { let id = UUID(); let target: String; let to: String; let count: Int }

    @State private var corrections: [Pair] = []
    @State private var pronunciations: [Pair] = []
    @State private var pending: [Pend] = []
    @State private var threshold = 2
    @State private var newFrom = ""
    @State private var newTo = ""
    @State private var newWord = ""
    @State private var newSay = ""
    @State private var path = ""
    @AppStorage("learnFromEdits") private var learnEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                correctionsSection
                pronunciationsSection
                if !pending.isEmpty { learningSection }
                settingsSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
        .onAppear(perform: reload)
    }

    private var correctionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Corrections")
            if corrections.isEmpty {
                Text("Nothing yet. Fix a word below — or open any dictation in History and teach it from there.")
                    .font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(corrections) { p in
                        pairRow(p.a, p.b) { Lexicon.shared.forget(p.a); reload() }
                        Hairline()
                    }
                }
            }
            addPairRow(a: $newFrom, ap: "heard…", b: $newTo, bp: "should be…") {
                Lexicon.shared.learnExplicit(from: newFrom, to: newTo); newFrom = ""; newTo = ""; reload()
            }
            .padding(.top, 8)
        }
    }

    private var pronunciationsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Pronunciations")
            if pronunciations.isEmpty {
                Text("Nothing yet. Add a word and how to say it — read-aloud will use it.")
                    .font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(pronunciations) { p in
                        pairRow(p.a, p.b) { Lexicon.shared.forgetPronunciation(p.a); reload() }
                        Hairline()
                    }
                }
            }
            addPairRow(a: $newWord, ap: "word…", b: $newSay, bp: "say it like…") {
                Lexicon.shared.setPronunciation(word: newWord, say: newSay); newWord = ""; newSay = ""; reload()
            }
            .padding(.top, 8)
        }
    }

    private var learningSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Learning")
            Text("warble is tallying these — they become rules once you've fixed them \(threshold)×.")
                .font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
            VStack(spacing: 0) {
                ForEach(pending) { p in
                    HStack(spacing: 8) {
                        Text(p.to).font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
                        Text("· \(p.count)/\(threshold)").font(.system(size: 11)).monospacedDigit().foregroundStyle(WarbleTheme.mist)
                        Spacer()
                        TrashButton { Lexicon.shared.forgetPending(p.target); reload() }
                    }
                    .padding(.vertical, 8)
                    if p.id != pending.last?.id { Hairline() }
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Settings")
            Toggle(isOn: $learnEnabled) {
                Text("Learn words from my in-place edits").font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
            }
            .tint(WarbleTheme.electric)
            .padding(.vertical, 8)
            Hairline()
            Stepper(value: $threshold, in: 1...9) {
                Text("Promote after \(threshold) fixes").font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
            }
            .onChange(of: threshold) { v in Lexicon.shared.learnThreshold = v }
            .padding(.vertical, 8)
            Hairline()
            VStack(alignment: .leading, spacing: 4) {
                Text("Dictionary file").font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
                Text(path).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 8) {
                    Button("Choose…") { choose() }
                    Button("Default") { Lexicon.shared.resetLocation(); reload() }
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([Lexicon.shared.fileURL]) }
                }
                .font(.system(size: 12))
                .padding(.top, 4)
            }
            .padding(.top, 8)
        }
    }

    // MARK: helpers

    private func pairRow(_ a: String, _ b: String, delete: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(a).font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(WarbleTheme.mist)
            Text(b).font(.system(size: 13)).foregroundStyle(WarbleTheme.electricText)
            Spacer()
            TrashButton(action: delete)
        }
        .padding(.vertical, 8)
    }
    private func addPairRow(a: Binding<String>, ap: String, b: Binding<String>, bp: String, add: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            TextField(ap, text: a).textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(WarbleTheme.mist)
            TextField(bp, text: b).textFieldStyle(.roundedBorder)
            Button("Add", action: add).disabled(a.wrappedValue.isEmpty || b.wrappedValue.isEmpty)
        }
    }
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { Lexicon.shared.setLocation(url); reload() }
    }
    private func reload() {
        Lexicon.shared.load()
        corrections = Lexicon.shared.corrections.map { Pair(a: $0.key, b: $0.value) }.sorted { $0.a < $1.a }
        pronunciations = Lexicon.shared.pronunciations.map { Pair(a: $0.key, b: $0.value) }.sorted { $0.a < $1.a }
        pending = Lexicon.shared.pending.map { Pend(target: $0.key, to: $0.value.to, count: $0.value.count) }.sorted { $0.to < $1.to }
        threshold = Lexicon.shared.learnThreshold
        path = Lexicon.shared.fileURL.path
    }
}

/// The destructive affordance appears on approach: mist at rest, brightening to text-hi on hover.
/// The trash glyph carries the meaning — no red (One-Accent Rule: the only non-blue chroma is warn,
/// failures only).
struct TrashButton: View {
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "trash").font(.system(size: 12))
                .foregroundStyle(hovered ? WarbleTheme.textHi : WarbleTheme.mist)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
