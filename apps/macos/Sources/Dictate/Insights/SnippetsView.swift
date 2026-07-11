import SwiftUI
import AppKit

/// Snippets, the dashboard's local text-expansion editor (ROADMAP 0.5): a spoken trigger phrase
/// becomes canned text — a signature, an address, a standard reply — matched case-insensitively
/// while you dictate. Same layout/idiom as DictionaryView: sections sit directly on the
/// background, rows are hairline-divided, no boxes. Wired straight to Snippets (Lexicon's
/// sibling); Snippets has no publisher, so we reload after each edit.
struct SnippetsView: View {
    struct Row: Identifiable { let id = UUID(); let trigger: String; let expansion: String }

    @State private var rows: [Row] = []
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var editingKey: String? // the lowercased trigger being edited, if any
    @State private var path = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                snippetsSection
                fileSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
        .onAppear(perform: reload)
    }

    private var snippetsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Snippets")
            if rows.isEmpty {
                Text("Nothing yet. Add a trigger phrase below — say it while dictating and warble types the text you saved instead of the words you spoke (e.g. \u{201C}sign off\u{201D} → your email signature).")
                    .font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { r in
                        snippetRow(r)
                        Hairline()
                    }
                }
            }
            editorRow.padding(.top, 8)
        }
    }

    /// One trigger → expansion row. Tapping the text loads it into the editor below (edit); the
    /// trash icon deletes outright — the same two affordances Dictionary's rows offer.
    private func snippetRow(_ r: Row) -> some View {
        HStack(spacing: 8) {
            Button { load(r) } label: {
                HStack(spacing: 8) {
                    Text(r.trigger).font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(WarbleTheme.mist)
                    Text(firstLine(r.expansion)).font(.system(size: 13)).foregroundStyle(WarbleTheme.electricText)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            TrashButton {
                Snippets.shared.forget(r.trigger)
                if editingKey == r.trigger.lowercased() { clearEditor() }
                reload()
            }
        }
        .padding(.vertical, 8)
    }

    /// The add/edit form: a one-line trigger field + a multi-line expansion editor (the reader
    /// idiom from HistoryView's transcript editor — the one place a box is earned), Add/Save +
    /// Cancel while editing.
    private var editorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("trigger phrase (e.g. \u{201C}sign off\u{201D})…", text: $trigger)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $expansion)
                .font(.system(size: 13))
                .foregroundStyle(WarbleTheme.textHi)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64)
                .padding(6)
                .background(WarbleTheme.ink, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(WarbleTheme.line, lineWidth: 1))
            HStack(spacing: 8) {
                Button(editingKey == nil ? "Add" : "Save") {
                    // Renaming a trigger while editing must retire the old key — set() alone would
                    // only add the new one, leaving the original behind as an orphan duplicate.
                    if let old = editingKey, old != trigger.trimmingCharacters(in: .whitespaces).lowercased() {
                        Snippets.shared.forget(old)
                    }
                    Snippets.shared.set(trigger: trigger, expansion: expansion)
                    clearEditor()
                    reload()
                }
                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty
                          || expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editingKey != nil {
                    Button("Cancel") { clearEditor() }
                }
            }
            .font(.system(size: 12))
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Snippets file").font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
            Text(path).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist).lineLimit(1).truncationMode(.middle)
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([Snippets.shared.fileURL]) }
                .font(.system(size: 12))
                .padding(.top, 4)
        }
    }

    // MARK: helpers

    private func load(_ r: Row) {
        editingKey = r.trigger.lowercased()
        trigger = r.trigger
        expansion = r.expansion
    }
    private func clearEditor() {
        editingKey = nil
        trigger = ""
        expansion = ""
    }
    private func firstLine(_ s: String) -> String {
        s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? s
    }
    private func reload() {
        Snippets.shared.load()
        rows = Snippets.shared.snippets.map { Row(trigger: $0.key, expansion: $0.value) }.sorted { $0.trigger < $1.trigger }
        path = Snippets.shared.fileURL.path
    }
}
