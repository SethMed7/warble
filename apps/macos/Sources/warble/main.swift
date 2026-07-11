import AppKit
import Speak
import Dictate
import Shared

// warble was "voz" through 0.1.8 — move an existing ~/.voz home into place before ANYTHING
// (including the CLI modes below) reads the dictionary, history, or warm-server venvs.
AIStore.migrateLegacyHome()

// Headless smoke-test modes (CI / dev) come first, so they never spin up UI or
// touch permissions. Each capability owns its own flags; the first to claim the
// args wins. Everything below runs entirely on-device.
let args = CommandLine.arguments

if args.contains("--version") {
    print("warble \((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.2.0")"); exit(0)
}
if args.contains("--errors") { // the cause-naming taxonomy of both flows, asserted by regression.sh
    DictateCLI.printErrors(); SpeakCLI.printErrors(); exit(0)
}
if SpeakCLI.handle(args) { exit(0) }    // --speak "text"
if DictateCLI.handle(args) { exit(0) }  // --clean / --cleanup / --cleanup-level / --transcribe / --engine / --apply / --selftest
if OnboardingCLI.handle(args) { exit(0) } // --onboarding-state / --render-onboarding (DEBUG)

// Single instance: if warble is already running, surface that one and quit. This is the guard against
// duplication — you never get two menu-bar icons, or two sets of warm ASR/LLM servers competing over
// the one ~/.warble. (The CLI modes above already returned, so they're unaffected.)
if let bid = Bundle.main.bundleIdentifier {
    let mine = ProcessInfo.processInfo.processIdentifier
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        .first(where: { $0.processIdentifier != mine }) {
        running.activate(options: [.activateIgnoringOtherApps])
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // launch as menu-bar only; AppDelegate flips to .regular per the Dock-icon pref + open windows
app.run()
