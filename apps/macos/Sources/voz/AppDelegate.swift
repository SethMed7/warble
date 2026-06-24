import AppKit
import Speak
import Dictate
import Shared
import Sparkle

/// voz — the voice layer for your Mac. One menu-bar app, two capabilities:
///   • Dictate — hold Fn, speak, release; the cleaned text is typed where your cursor is.
///   • Read aloud — select text anywhere, press ⌃V; voz reads it and follows along.
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
        NotificationCenter.default.addObserver(forName: .vozAutoUpdateChanged, object: nil, queue: .main) {
            [weak self] _ in self?.applyAutoUpdatePref()
        }

        // First launch: a native welcome so a new user isn't dropped into a bare menu bar.
        if WelcomeWindow.shouldShow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WelcomeWindow.shared.open() }
        }

        // QA hook (off by default): VOZ_FORCE_TUTORIAL=1 opens Insights and replays the coachmark tour,
        // so the first-run walkthrough can be previewed without going through engine setup each time.
        if ProcessInfo.processInfo.environment["VOZ_FORCE_TUTORIAL"] == "1" {
            UserDefaults.standard.set(false, forKey: "didShowTutorial")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { InsightsWindow.shared.openTutorial() }
        }
        // QA hook (off by default): VOZ_FORCE_SETUP=1 opens the "Set up better engines" window on launch.
        if ProcessInfo.processInfo.environment["VOZ_FORCE_SETUP"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { SetupWindow.shared.open() }
        }
        // QA hook (off by default): VOZ_FORCE_INSIGHTS=1 opens the Insights window on Home — handy for
        // eyeballing the dashboard/sidebar without dictating first.
        if ProcessInfo.processInfo.environment["VOZ_FORCE_INSIGHTS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { InsightsWindow.shared.openHome() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dictate.shutdown() // stop the warm ASR server we may have spawned
        speak.shutdown()   // stop any read + kill the Kokoro subprocess and delete its temp audio
    }

    /// Mirror the in-app "Install updates automatically" toggle onto Sparkle's scheduled checker.
    private func applyAutoUpdatePref() {
        updaterController.updater.automaticallyChecksForUpdates = InsightStore.shared.autoUpdateEnabled
    }

    /// Show the highest-priority capability's icon; when both are idle, show the brand mark.
    private func applyIcon() {
        let winner = dictateIcon.priority >= speakIcon.priority ? dictateIcon : speakIcon
        // Resting (both idle) → the voz brand V. Active → the live SF Symbol, so a hot mic or an
        // in-progress read still reads at a glance.
        if winner.priority == 0 {
            statusItem.button?.image = VozMark.menuBarTemplate()
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: winner.symbol, accessibilityDescription: "voz")
        }
    }

    /// One menu, two sections. Rebuilt on demand (e.g. when a capability toggles a checkmark).
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false // dictation has disabled info rows

        let header = NSMenuItem(title: "voz", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        speak.menuItems().forEach { menu.addItem($0) }
        menu.addItem(.separator())
        dictate.menuItems().forEach { menu.addItem($0) }
        menu.addItem(.separator())

        let setup = NSMenuItem(title: "Set up better engines…", action: #selector(runBootstrap), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        menu.addItem(.separator())

        // Sparkle owns this action; it opens the standard update flow (and reports "you're up to date").
        let updates = NSMenuItem(title: "Check for Updates…",
                                 action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                 keyEquivalent: "")
        updates.target = updaterController
        menu.addItem(updates)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit voz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// Open the native, in-app setup screen — engine cards with Install buttons and live progress,
    /// matching the rest of the app. No Terminal: each engine downloads its model in-process (real %)
    /// and runs only its environment step headlessly. (Replaced the old Terminal `.command` flow.)
    @objc private func runBootstrap() { SetupWindow.shared.open() }
}
