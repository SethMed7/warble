import SwiftUI
import AppKit

/// Shortcuts — the dashboard's binding editor (ROADMAP 0.5 "multi-shortcut + mouse bindings"):
/// up to three extra dictation triggers besides the built-in Fn — right ⌘ / right ⌥ / F13–F19 /
/// mouse buttons 3–10, each as hold-to-talk or a double-tap hands-free toggle. Bindings are
/// aliases of Fn, not modes: same pill, same Esc, same everything. Same layout/idiom as
/// SnippetsView (its 0.5 sibling): sections sit directly on the background, hairline-divided
/// rows, no boxes. Edits apply live — the store saves, then HotKey.reload() re-registers without
/// a relaunch; while Dictate is off, nothing is registered at all (the per-mode permission law).
/// The picker IS the safety rail: only keys and buttons macOS leaves free are offered, so Esc,
/// ⌃V, and the system's own keys can't even be picked; duplicate/over-cap adds are rejected
/// inline with the same plain reason `--bindings add` prints.
struct ShortcutsView: View {
    @State private var rows: [DictationBinding] = []
    @State private var trigger: BindingTrigger = .rightCommand
    @State private var gesture: BindingGesture = .hold
    @State private var rejection: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Dictation shortcuts")
                Text("Fn is built in; add up to \(Bindings.maxExtra) more triggers — a spare modifier, an F-key, or a mouse thumb button. Each works exactly like Fn: same pill, Esc cancels, and warble only listens for it while Dictate is on. A binding never swallows the key or click itself, so pick one your apps don't already use.")
                    .font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)

                VStack(spacing: 0) {
                    fnRow
                    Hairline()
                    ForEach(rows, id: \.self) { b in
                        bindingRow(b)
                        Hairline()
                    }
                }
                editorRow.padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WarbleTheme.black)
        .onAppear(perform: reload)
    }

    /// The documented default, shown but locked — Fn can't be removed (the tour, the README, and
    /// the pill's hint all teach it).
    private var fnRow: some View {
        HStack(spacing: 8) {
            Text("Fn").font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
            Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
            Text("hold to talk · double-tap for hands-free").font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(WarbleTheme.mist)
            Text("built in").font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
        }
        .padding(.vertical, 8)
    }

    private func bindingRow(_ b: DictationBinding) -> some View {
        HStack(spacing: 8) {
            Text(b.trigger.display).font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
            Text(b.gesture.display).font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
            Spacer()
            TrashButton {
                Bindings.shared.remove(b)
                HotKey.shared.reload() // live — the tap re-registers, no relaunch
                rejection = nil
                reload()
            }
        }
        .padding(.vertical, 8)
    }

    /// The add form: trigger + gesture pickers and Add. A rejected add (duplicate, over the cap)
    /// shows its plain reason — warn + glyph, the blocked-state styling (DESIGN.md).
    private var editorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $trigger) {
                    ForEach(BindingTrigger.allCases, id: \.self) { t in
                        Text(t.display).tag(t)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 190)
                .tint(WarbleTheme.electric)
                Picker("", selection: $gesture) {
                    ForEach(BindingGesture.allCases, id: \.self) { g in
                        Text(g.display).tag(g)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 170)
                .tint(WarbleTheme.electric)
                Button("Add") {
                    switch Bindings.shared.add(DictationBinding(trigger: trigger, gesture: gesture)) {
                    case .added:
                        HotKey.shared.reload() // live — the tap re-registers, no relaunch
                        rejection = nil
                        reload()
                    case .rejected(let reason):
                        rejection = reason
                    }
                }
                .disabled(rows.count >= Bindings.maxExtra)
            }
            .font(.system(size: 12))
            if let rejection {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                    Text(rejection).font(.system(size: 11))
                }
                .foregroundStyle(WarbleTheme.warn)
            } else if rows.count >= Bindings.maxExtra {
                Text("Up to \(Bindings.maxExtra) bindings besides Fn — remove one to add another.")
                    .font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
            }
        }
    }

    private func reload() {
        Bindings.shared.load()
        rows = Bindings.shared.list
    }
}
