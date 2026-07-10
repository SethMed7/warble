import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Data & Privacy: what's kept, the toggles that control it, and clear/export. Everything is local to
/// ~/.voz and never uploaded.
struct DataPrivacyView: View {
    @ObservedObject var store: InsightStore
    @State private var confirmClear = false
    @State private var clearHovered = false
    /// App-level pref, read by the AppDelegate's Dock policy — this view only writes the default
    /// and posts the change signal; the lifecycle side owns the actual .accessory ↔ .regular flip.
    @AppStorage("voz.dockIcon") private var dockIconMode = "whileWindowsOpen"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Data & Privacy",
                           subtitle: "Everything lives on your Mac, in ~/.voz — never uploaded. Audio is deleted unless you keep it.")

                VStack(alignment: .leading, spacing: 0) {
                    toggleRow("Keep dictation history",
                              "Store the transcript text so you can search & re-read it. Off = stats only, no text.",
                              get: { store.historyEnabled }, set: { store.historyEnabled = $0 })
                    Divider().overlay(VozTheme.line).padding(.vertical, 12)
                    toggleRow("Save recordings",
                              "Keep the audio so you can replay a dictation. Off = audio is deleted after transcription.",
                              get: { store.saveAudio }, set: { store.saveAudio = $0 })
                    Divider().overlay(VozTheme.line).padding(.vertical, 12)
                    toggleRow("Skip password fields",
                              "Never store text or audio when a secure (password) field is focused.",
                              get: { store.excludeSecureFields }, set: { store.excludeSecureFields = $0 })
                }
                .cardStyle()

                // Insights AI: the optional, default-off generative layer. The master toggle gates the
                // whole feature; the auto-refresh control below it is dimmed/disabled while it's off.
                VStack(alignment: .leading, spacing: 0) {
                    Text("Insights AI").font(.system(size: 15, weight: .semibold)).foregroundStyle(VozTheme.textHi)
                        .padding(.bottom, 12)
                    toggleRow("Insights AI",
                              "Optional on-device summaries, suggested words, and nudges. Default off; reads only your local stats.",
                              get: { store.aiInsightsEnabled }, set: { store.aiInsightsEnabled = $0 })
                    Divider().overlay(VozTheme.line).padding(.vertical, 12)
                    toggleRow("Refresh automatically (weekly)",
                              "On: auto-refresh when you open Insights. Off: only when you tap Regenerate.",
                              get: { store.aiInsightsAutoRefresh }, set: { store.aiInsightsAutoRefresh = $0 })
                        .disabled(!store.aiInsightsEnabled)
                        .opacity(store.aiInsightsEnabled ? 1 : 0.45)
                }
                .cardStyle()

                // Updates: the "Check for Updates…" menu item is always available; this toggle controls
                // only the quiet automatic (≈daily) background check, so the choice stays transparent.
                VStack(alignment: .leading, spacing: 0) {
                    Text("Updates").font(.system(size: 15, weight: .semibold)).foregroundStyle(VozTheme.textHi)
                        .padding(.bottom, 12)
                    toggleRow("Install updates automatically",
                              "On: voz quietly checks about once a day and offers new versions. Off: manual only — use \u{201C}Check for Updates…\u{201D} in the menu. Either way, updates are signed and stay on your Mac.",
                              get: { store.autoUpdateEnabled }, set: { store.autoUpdateEnabled = $0 })
                }
                .cardStyle()

                // App: voz is a menu-bar app first — this picks when it also shows in the Dock.
                VStack(alignment: .leading, spacing: 0) {
                    Text("App").font(.system(size: 15, weight: .semibold)).foregroundStyle(VozTheme.textHi)
                        .padding(.bottom, 12)
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Dock icon").font(.system(size: 13)).foregroundStyle(VozTheme.textHi)
                            Text("voz lives in the menu bar. Choose when it also appears in the Dock with a full app menu.")
                                .font(.system(size: 11)).foregroundStyle(VozTheme.mist)
                        }
                        Spacer()
                        Picker("", selection: $dockIconMode) {
                            Text("While a window is open").tag("whileWindowsOpen")
                            Text("Always").tag("always")
                            Text("Never").tag("never")
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 210)
                        .tint(VozTheme.electric)
                        .onChange(of: dockIconMode) { _ in
                            NotificationCenter.default.post(name: Notification.Name("voz.dockIconModeChanged"), object: nil)
                        }
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your data").font(.system(size: 15, weight: .semibold)).foregroundStyle(VozTheme.textHi)
                    Text("\(store.dictations.count) dictations · \(store.reads.count) reads · \(store.audioSummary)")
                        .font(.system(size: 12)).foregroundStyle(VozTheme.mist)
                    HStack(spacing: 8) {
                        Button("Export…") { HistoryExport.run(store) }
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.dir]) }
                        Spacer()
                        // Destructive stays neutral (One-Accent Rule: no red) — the confirm alert is
                        // the safety net; hover brightens mist to text-hi like every ghost button.
                        Button { confirmClear = true } label: {
                            Text("Clear all history")
                                .foregroundStyle(clearHovered ? VozTheme.textHi : VozTheme.mist)
                        }
                        .buttonStyle(.plain)
                        .onHover { clearHovered = $0 }
                    }
                    .font(.system(size: 12))
                }
                .cardStyle()
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VozTheme.black)
        .alert("Clear all history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { store.clearAll() }
        } message: {
            Text("Deletes every saved transcript and recording. This can't be undone.")
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String,
                           get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: get, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(VozTheme.textHi)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(VozTheme.mist)
            }
        }
        .tint(VozTheme.electric)
    }
}

/// One export path for the pane button and the window toolbar — same panel, same JSON.
enum HistoryExport {
    static func run(_ store: InsightStore) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "voz-history.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportJSON().write(to: url)
        }
    }
}
