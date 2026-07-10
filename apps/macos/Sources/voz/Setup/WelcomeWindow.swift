import AppKit
import SwiftUI
import Shared

/// Shown once, on first launch, so a brand-new user isn't dropped into an empty menu bar wondering
/// what to do. Explains the two gestures and offers the one-click jump to engine setup.
final class WelcomeWindow {
    static let shared = WelcomeWindow()
    private var window: NSWindow?

    private static let key = "didShowWelcome"
    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func markShown() { UserDefaults.standard.set(true, forKey: key) }

    func open() {
        if window == nil {
            let host = NSHostingView(rootView: WelcomeView { [weak self] in self?.window?.close() })
            host.sizingOptions = [] // critical: don't let the hosting view resize the window to its content
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.contentView = host
            w.center()
            window = w
        }
        Self.markShown()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 28)
            Image(systemName: "waveform")
                .font(.system(size: 38, weight: .semibold)).foregroundColor(Theme.electric.color)
            Text("Welcome to voz").font(.system(size: 24, weight: .bold)).foregroundColor(Theme.textHi.color).padding(.top, 12)
            Text("The voice layer for your Mac. Two gestures — that's it.")
                .font(.system(size: 13)).foregroundColor(Theme.mist.color).padding(.top, 4)

            VStack(spacing: 12) {
                gesture("mic.fill", "Speak to type", "Hold **Fn**, talk, release. voz types the cleaned text where your cursor is — in any app.")
                gesture("text.viewfinder", "Select to hear", "Select text anywhere and press **⌃V**. voz reads it aloud in a warm voice.")
            }
            .padding(.horizontal, 28).padding(.top, 24)

            Text("It works right now on Apple's built-in engines. Want sharper dictation, neural voices, or AI cleanup? They install on demand — your call.")
                .font(.system(size: 12)).foregroundColor(Theme.mist.color).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30).padding(.top, 22)

            Spacer()
            HStack(spacing: 12) {
                Button("Maybe later") { onClose() }.buttonStyle(GhostButton())
                Button("Set up better engines") { onClose(); SetupWindow.shared.open() }
                    .buttonStyle(FilledButton())
            }
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.black.color)
    }

    private func gesture(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundColor(Theme.electric.color)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.textHi.color)
                Text(.init(body)).font(.system(size: 12)).foregroundColor(Theme.mist.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.ink.color))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.color, lineWidth: 1))
    }
}

/// The quiet decline: mist label, no fill — hover brightens it to text-hi, and focus draws the
/// same crest ring as the filled button (a color shift alone is not focus).
private struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    // Not named `Body`: that would shadow ButtonStyle's associated type and break conformance.
    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(hovered ? Theme.textHi.color : Theme.mist.color)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Theme.electricBright.color, lineWidth: 2)
                    .padding(-2)
                    .opacity(focused ? 1 : 0))
                .onHover { hovered = $0 }
        }
    }
}
