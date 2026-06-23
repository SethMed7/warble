import AppKit
import SwiftUI

/// Hosts the SwiftUI Insights dashboard in a single dark NSWindow — the one SwiftUI surface in an
/// otherwise-AppKit app. Mirrors the Dictionary window's dark chrome + accessory activation.
public final class InsightsWindow {
    public static let shared = InsightsWindow()
    private var window: NSWindow?
    private let nav = InsightsNav()

    /// Deep-link from the menu (internal). The app coordinator uses openHome()/openTutorial().
    func open(section: InsightsSection = .home) { openImpl(section: section, tutorial: false) }
    /// Public entry points (callable from the app target, which can't see InsightsSection).
    public func openHome() { openImpl(section: .home, tutorial: false) }
    /// Open Home and run the first-time, skippable tutorial — e.g. right after engine setup is done.
    public func openTutorial() { openImpl(section: .home, tutorial: true) }

    private func openImpl(section: InsightsSection, tutorial: Bool) {
        if window == nil {
            let host = NSHostingView(rootView: InsightsRootView(store: InsightStore.shared, nav: nav))
            host.sizingOptions = [] // don't let the hosting view resize the window to its content
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "voz Insights"
            w.titleVisibility = .hidden // the sidebar already brands it; don't draw the title twice in the bar
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.contentView = host
            w.setFrameAutosaveName("voz.insights")
            w.center()
            window = w
        }
        nav.section = section
        if tutorial, !UserDefaults.standard.bool(forKey: "didShowTutorial") { nav.showTutorial = true }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
