import AppKit
import Sparkle

/// The real main menu — the menu bar shows it only while the Dock policy is .regular, but its key
/// equivalents (⌘W, ⌘C, ⌘,…) route to the key window in every mode, so the dashboard's shortcuts
/// work even as a pure menu-bar app. Built once at launch.
enum MainMenu {
    static func build(updater: SPUStandardUpdaterController, delegate: AppDelegate) -> NSMenu {
        let bar = NSMenu()
        attach(appMenu(updater: updater, delegate: delegate), to: bar)
        attach(fileMenu(), to: bar)
        attach(editMenu(), to: bar)
        let window = windowMenu()
        attach(window, to: bar)
        NSApp.windowsMenu = window // AppKit appends the live window list for us
        return bar
    }

    /// Wrap a menu in the bar-level item that carries it.
    private static func attach(_ menu: NSMenu, to bar: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        bar.addItem(item)
    }

    /// The app menu. The title string is cosmetic — the bar shows the process name "voz".
    private static func appMenu(updater: SPUStandardUpdaterController, delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "voz")
        let about = NSMenuItem(title: "About voz",
                               action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                               keyEquivalent: "")
        about.target = NSApp
        menu.addItem(about)
        menu.addItem(.separator())
        // Sparkle owns this action — same wiring as the status-menu item.
        let updates = NSMenuItem(title: "Check for Updates…",
                                 action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                 keyEquivalent: "")
        updates.target = updater
        menu.addItem(updates)
        menu.addItem(.separator())
        // ⌘, deep-links to Data & Privacy — the dashboard section that doubles as Settings.
        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settings.target = delegate
        menu.addItem(settings)
        menu.addItem(.separator())
        // A .regular app is expected to honor ⌘H; these cost zero code.
        menu.addItem(NSMenuItem(title: "Hide voz", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.option, .command]
        menu.addItem(hideOthers)
        menu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
                                keyEquivalent: ""))
        menu.addItem(.separator())
        // Runs the existing applicationWillTerminate teardown (engine shutdowns).
        menu.addItem(NSMenuItem(title: "Quit voz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        // First responder closes the key window; its willClose then drives the Dock-policy machine.
        menu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        return menu
    }

    /// The full standard Edit menu — the reason this menu exists: SwiftUI text fields inside
    /// NSHostingView only get cut/copy/paste/undo via main-menu key equivalents; without it,
    /// ⌘C in the History search field just beeps. Every item targets the first responder.
    /// (No collision with voz's global hotkeys: read-aloud is ⌃V not ⌘V, dictation is Fn.)
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        // undo:/redo: are string selectors — the standard AppKit idiom; there's no @objc method to reference.
        menu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)),
                                keyEquivalent: ""))
        return menu
    }
}
