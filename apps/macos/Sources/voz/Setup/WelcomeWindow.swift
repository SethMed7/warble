import AppKit
import SwiftUI

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

private enum T {
    static let black = Color(red: 0x07 / 255.0, green: 0x08 / 255.0, blue: 0x0C / 255.0)
    static let electric = Color(red: 0x2E / 255.0, green: 0x74 / 255.0, blue: 0xFF / 255.0)
    static let mist = Color(red: 0x8B / 255.0, green: 0x87 / 255.0, blue: 0x94 / 255.0)
    static let textHi = Color(red: 0.93, green: 0.94, blue: 0.96)
    static let ink = Color(red: 0x16 / 255.0, green: 0x15 / 255.0, blue: 0x20 / 255.0)
    static let line = Color(red: 0x2A / 255.0, green: 0x28 / 255.0, blue: 0x33 / 255.0)
}

private struct WelcomeView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 28)
            Image(systemName: "waveform")
                .font(.system(size: 38, weight: .semibold)).foregroundColor(T.electric)
            Text("Welcome to voz").font(.system(size: 24, weight: .bold)).foregroundColor(T.textHi).padding(.top, 12)
            Text("The voice layer for your Mac. Two gestures — that's it.")
                .font(.system(size: 13)).foregroundColor(T.mist).padding(.top, 4)

            VStack(spacing: 12) {
                gesture("mic.fill", "Speak to type", "Hold **Fn**, talk, release. voz types the cleaned text where your cursor is — in any app.")
                gesture("text.viewfinder", "Select to hear", "Select text anywhere and press **⌃V**. voz reads it aloud in a warm voice.")
            }
            .padding(.horizontal, 28).padding(.top, 24)

            Text("It works right now on Apple's built-in engines. Want sharper dictation, neural voices, or AI cleanup? They install on demand — your call.")
                .font(.system(size: 12)).foregroundColor(T.mist).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30).padding(.top, 22)

            Spacer()
            HStack(spacing: 12) {
                Button("Maybe later") { onClose() }.buttonStyle(.plain).foregroundColor(T.mist)
                Button("Set up better engines") { onClose(); SetupWindow.shared.open() }
                    .buttonStyle(PrimaryButton())
            }
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.black)
    }

    private func gesture(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundColor(T.electric)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(T.textHi)
                Text(.init(body)).font(.system(size: 12)).foregroundColor(T.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(T.ink))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line, lineWidth: 1))
    }
}

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(T.electric.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}
