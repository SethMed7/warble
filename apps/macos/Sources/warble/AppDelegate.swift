import AppKit
import Speak
import Dictate
import Shared
import Sparkle

/// warble — the voice layer for your Mac. One menu-bar app, two capabilities:
///   • Dictate — hold Fn, speak, release; the cleaned text is typed where your cursor is.
///   • Read aloud — select text anywhere, press ⌃V; warble reads it and follows along.
///
/// Each capability is a self-contained controller from its own module. The app owns the
/// single shared status item and routes each capability's icon/menu updates through here,
/// so the two never fight over the menu bar. Everything is 100% on-device.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let speak = SpeakController()
    private let dictate = DictateController()

    // In-app updates (Sparkle): the only external dependency. Drives both the "Check for Updates…"
    // menu item and a quiet scheduled background check. `startingUpdater: true` begins the scheduled
    // checks once the app is running; Sparkle verifies every update against the embedded EdDSA public
    // key (SUPublicEDKey) before installing, and the feed (SUFeedURL) is read over HTTPS only.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // Each capability reports the icon it wants plus a priority; the higher-priority one owns the
    // shared status item (so a hot mic is never masked by read-aloud). Both idle → the brand mark.
    private var speakIcon = (priority: 0, symbol: "waveform")
    private var dictateIcon = (priority: 0, symbol: "waveform")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The real main menu, built once before any window can open. No menu bar shows while
        // .accessory, but AppKit still routes its key equivalents to the key window — it's what
        // makes ⌘W/⌘C/⌘,… work in the dashboard under every Dock-icon mode, including "never".
        NSApp.mainMenu = MainMenu.build(updater: updaterController, delegate: self)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        applyIcon()

        // Both capabilities share one menu-bar item; funnel their changes here.
        speak.onIcon = { [weak self] p, symbol in self?.speakIcon = (p, symbol); self?.applyIcon() }
        dictate.onIcon = { [weak self] p, symbol in self?.dictateIcon = (p, symbol); self?.applyIcon() }
        speak.onMenuRebuild = { [weak self] in self?.rebuildMenu() }
        dictate.onMenuRebuild = { [weak self] in self?.rebuildMenu() }
        // Log read-aloud usage to Insights (the store lives in the Dictate module; route reads to it).
        speak.onRead = { text, bid, name, voice in
            InsightStore.shared.recordRead(text: text, appBundleId: bid, appName: name, voice: voice)
        }

        speak.start()
        dictate.start()
        rebuildMenu()

        // Mirror the in-app "Install updates automatically" toggle (Insights ▸ Data & Privacy ▸ Updates)
        // onto Sparkle's scheduled checker now, and keep it in sync live. "Check for Updates…" in the
        // menu works regardless of this toggle.
        applyAutoUpdatePref()
        NotificationCenter.default.addObserver(forName: .warbleAutoUpdateChanged, object: nil, queue: .main) {
            [weak self] _ in self?.applyAutoUpdatePref()
        }

        // Hybrid Dock policy (the Rectangle/Ice pattern): a real app window (Dashboard, Setup,
        // Welcome) becoming key promotes to .regular — Dock icon + menu bar — and the last one
        // closing demotes back to .accessory. The "Show Dock icon" pref can pin either way; the
        // dashboard's control posts the change signal, behavior lives entirely here.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) {
            [weak self] note in self?.windowDidBecomeKey(note)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
            [weak self] note in self?.windowWillClose(note)
        }
        NotificationCenter.default.addObserver(forName: dockIconModeChanged, object: nil, queue: .main) {
            [weak self] _ in self?.applyDockPolicy()
        }
        applyDockPolicy() // honor "always" from a previous run; no key window at launch, so no focus steal

        // Post-macOS-update re-verify (ROADMAP 0.4): silently re-check previously-granted
        // permissions after an OS update; a revocation becomes one quiet menu row (rebuildMenu),
        // never a dialog.
        PermissionNotice.checkAtLaunch()

        // First launch: the welcome tour (card flow) so a new user isn't dropped into a bare menu
        // bar. Shown once, ever — existing installs are gated out by the migrated didShowWelcome key.
        if WelcomeWindow.shouldShow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WelcomeWindow.shared.open() }
        }
        // QA hook (off by default): WARBLE_FORCE_ONBOARDING=1 reopens the welcome tour on launch,
        // so the card flow can be walked without resetting the first-run keys.
        if ProcessInfo.processInfo.environment["WARBLE_FORCE_ONBOARDING"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WelcomeWindow.shared.open() }
        }

        // QA hook (off by default): WARBLE_FORCE_TUTORIAL=1 opens Insights and replays the coachmark tour,
        // so the first-run walkthrough can be previewed without going through engine setup each time.
        if ProcessInfo.processInfo.environment["WARBLE_FORCE_TUTORIAL"] == "1" {
            UserDefaults.standard.set(false, forKey: "didShowTutorial")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { InsightsWindow.shared.openTutorial() }
        }
        // QA hook (off by default): WARBLE_FORCE_SETUP=1 opens the "Set up better engines" window on launch.
        if ProcessInfo.processInfo.environment["WARBLE_FORCE_SETUP"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { SetupWindow.shared.open() }
        }
        // QA hook (off by default): WARBLE_FORCE_INSIGHTS=1 opens the Insights window on Home — handy for
        // eyeballing the dashboard/sidebar without dictating first.
        if ProcessInfo.processInfo.environment["WARBLE_FORCE_INSIGHTS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { InsightsWindow.shared.openHome() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dictate.shutdown() // stop the warm ASR server we may have spawned
        speak.shutdown()   // stop any read + kill the Kokoro subprocess and delete its temp audio
    }

    /// Dock icon clicked (only reachable while .regular). No visible windows → open the dashboard;
    /// otherwise let AppKit do its default bring-forward/deminiaturize.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { InsightsWindow.shared.openHome(); return false }
        return true
    }

    // MARK: Dock policy — .accessory ↔ .regular, a pure function of the pref + our open windows

    private var dockDemotion: DispatchWorkItem? // pending drop to .accessory — debounced, see windowWillClose

    /// True for warble's real app windows — Dashboard, Setup, Welcome — the ones that summon the Dock
    /// icon. Overlays/pills are NSPanels; Sparkle's update windows arrive wrapped in SU*/SPU*
    /// window controllers; ours are bare titled NSWindows we create ourselves.
    private func isAppWindow(_ w: NSWindow) -> Bool {
        guard !(w is NSPanel), w.styleMask.contains(.titled) else { return false }
        if let wc = w.windowController {
            let cls = String(describing: type(of: wc))
            if cls.hasPrefix("SU") || cls.hasPrefix("SPU") { return false } // Sparkle's alert/status/permission windows
        }
        return true
    }

    /// The app windows currently "open" from the user's point of view. Miniaturized counts — a window
    /// living in the Dock must keep the Dock icon alive, and `isVisible` is false while miniaturized.
    private var appWindows: [NSWindow] {
        NSApp.windows.filter { isAppWindow($0) && ($0.isVisible || $0.isMiniaturized) }
    }

    private func windowDidBecomeKey(_ note: Notification) {
        guard let w = note.object as? NSWindow, isAppWindow(w) else { return }
        dockDemotion?.cancel(); dockDemotion = nil        // a live window vetoes any pending demotion
        guard DockIconMode.current != .never, NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        // Pitfall: after the policy flip the menu bar keeps showing the PREVIOUS app's menu until we
        // re-activate — and the activation must land on the runloop tick AFTER the flip to take.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)                   // re-assert key; the flip can drop key status
        }
    }

    /// Demotion is debounced: window→window handoffs (Welcome → Setup, Setup → tutorial) close one
    /// window and open the next in the same user action — demoting synchronously would flap
    /// .regular → .accessory → .regular inside one tick (the Dock icon blinks, focus can drop).
    /// The next window's didBecomeKey cancels the pending demotion; otherwise it re-checks and fires.
    private func windowWillClose(_ note: Notification) {
        guard let w = note.object as? NSWindow, isAppWindow(w) else { return }
        guard DockIconMode.current == .whileWindowsOpen else { return }
        // At willClose time the closing window is still isVisible — exclude it by identity.
        guard appWindows.allSatisfy({ $0 === w }) else { return } // another app window remains → stay .regular
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.appWindows.isEmpty else { return } // re-check: something reopened meanwhile
            NSApp.setActivationPolicy(.accessory)
        }
        dockDemotion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Reconcile the activation policy with the pref and the current window state. Called at launch
    /// and whenever the dashboard's "Show Dock icon" control posts a change.
    private func applyDockPolicy() {
        dockDemotion?.cancel(); dockDemotion = nil
        let want: NSApplication.ActivationPolicy
        switch DockIconMode.current {
        case .always:           want = .regular
        case .never:            want = .accessory
        case .whileWindowsOpen: want = appWindows.isEmpty ? .accessory : .regular
        }
        guard NSApp.activationPolicy() != want else { return }
        NSApp.setActivationPolicy(want)
        // Promoting while one of our windows is up (pref flipped from the dashboard): re-activate so
        // the main menu actually appears. At launch there's no key window, so this never steals focus.
        if want == .regular, let key = NSApp.keyWindow, isAppWindow(key) {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                key.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Mirror the in-app "Install updates automatically" toggle onto Sparkle's scheduled checker.
    private func applyAutoUpdatePref() {
        updaterController.updater.automaticallyChecksForUpdates = InsightStore.shared.autoUpdateEnabled
    }

    /// Show the highest-priority capability's icon; when both are idle, show the brand mark.
    private func applyIcon() {
        let winner = dictateIcon.priority >= speakIcon.priority ? dictateIcon : speakIcon
        // Resting (both idle) → the warble brand V. Active → the live SF Symbol, so a hot mic or an
        // in-progress read still reads at a glance.
        if winner.priority == 0 {
            statusItem.button?.image = WarbleMark.menuBarTemplate()
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: winner.symbol, accessibilityDescription: "warble")
        }
    }

    /// One menu, two capability blocks. Each block is a toggle row plus a submenu of detail rows,
    /// so the top level stays short — the toggles delimit the blocks, no separator needed between
    /// them. Rebuilt on demand (e.g. when a capability toggles a checkmark).
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false // the header row is explicitly disabled

        let header = NSMenuItem(title: "warble", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Post-macOS-update re-verify (ROADMAP 0.4): if an OS update silently revoked a granted
        // permission, ONE quiet notice row — the "Last error" idiom, but clickable: opening the
        // right Privacy pane is also the acknowledgment, so it never repeats. Never a dialog
        // (product.md §4.5); it retires by itself if the grant comes back.
        let revoked = PermissionNotice.pending()
        if !revoked.isEmpty {
            let notice = NSMenuItem(title: PermissionNotice.menuTitle(for: revoked),
                                    action: #selector(fixRevokedPermissions), keyEquivalent: "")
            notice.target = self
            notice.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "warning")
            notice.toolTip = "Open System Settings to grant it again — this notice shows once."
            menu.addItem(notice)
            menu.addItem(.separator())
        }

        dictate.menuItems().forEach { menu.addItem($0) }
        speak.menuItems().forEach { menu.addItem($0) }
        menu.addItem(.separator())

        let dashboard = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "i")
        dashboard.target = self
        menu.addItem(dashboard)
        menu.addItem(.separator())

        let setup = NSMenuItem(title: "Set up better engines…", action: #selector(runBootstrap), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)

        // Re-run the onboarding card flow anytime — it never reopens itself (product.md §4.5).
        let tour = NSMenuItem(title: "Welcome tour…", action: #selector(openWelcomeTour), keyEquivalent: "")
        tour.target = self
        menu.addItem(tour)

        // Sparkle owns this action; it opens the standard update flow (and reports "you're up to date").
        let updates = NSMenuItem(title: "Check for Updates…",
                                 action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                 keyEquivalent: "")
        updates.target = updaterController
        menu.addItem(updates)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit warble", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// Status-menu "Open Dashboard" — the Insights window is the app's main window now.
    @objc private func openDashboard() { InsightsWindow.shared.openHome() }

    /// Main-menu Settings… (⌘,) — the dashboard's Data & Privacy section doubles as Settings.
    @objc func openSettings() { InsightsWindow.shared.openData() }

    /// Open the native, in-app setup screen — engine cards with Install buttons and live progress,
    /// matching the rest of the app. No Terminal: each engine downloads its model in-process (real %)
    /// and runs only its environment step headlessly. (Replaced the old Terminal `.command` flow.)
    @objc private func runBootstrap() { SetupWindow.shared.open() }

    /// Menu "Welcome tour…" — reopen the onboarding card flow on demand.
    @objc private func openWelcomeTour() { WelcomeWindow.shared.open() }

    /// The revoked-permission notice row: clicking it opens the right Privacy pane AND retires the
    /// notice — the click is the acknowledgment, so it never repeats (never a dialog, never a nag).
    @objc private func fixRevokedPermissions() {
        let revoked = PermissionNotice.pending()
        guard !revoked.isEmpty else { return }
        NSWorkspace.shared.open(PermissionNotice.settingsURL(for: revoked))
        PermissionNotice.acknowledge()
        rebuildMenu()
    }
}

/// "Show Dock icon" — app-level pref (plain UserDefaults, warble. prefix per convention).
/// whileWindowsOpen is the Rectangle/Ice hybrid: Dock icon + main menu appear only while a real
/// app window (Dashboard, Setup, Welcome) is open; the menu-bar presence never changes.
private enum DockIconMode: String {
    case whileWindowsOpen, always, never
    static var current: DockIconMode {
        DockIconMode(rawValue: UserDefaults.standard.string(forKey: "warble.dockIcon") ?? "") ?? .whileWindowsOpen
    }
}

/// Posted by the dashboard's "Show Dock icon" control after it writes the default. No payload —
/// we re-read UserDefaults, the single source of truth. (Not KVO: the key contains a dot, which
/// UserDefaults KVO can't address, and this mirrors the .warbleAutoUpdateChanged pattern anyway.)
private let dockIconModeChanged = Notification.Name("warble.dockIconModeChanged")
