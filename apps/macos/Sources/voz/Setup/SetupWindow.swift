import AppKit
import SwiftUI
import Dictate

/// Hosts the native Setup screen in a single dark NSWindow — mirrors the Insights window's chrome, so
/// "Set up better engines…" feels like the rest of the app instead of dropping you into Terminal.
final class SetupWindow {
    static let shared = SetupWindow()
    private var window: NSWindow?

    func open() {
        EngineSetup.shared.refresh()
        if window == nil {
            let host = NSHostingView(rootView: SetupView(setup: EngineSetup.shared, onDone: { [weak self] in
                self?.window?.close()
                InsightsWindow.shared.openTutorial() // finish setup → open Insights with the first-time tutorial
            }))
            host.sizingOptions = [] // critical: don't let the hosting view resize the window to its content
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "voz · Set up better engines"
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.contentView = host
            w.setFrameAutosaveName("voz.setup")
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
