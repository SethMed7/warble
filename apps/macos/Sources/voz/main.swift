import AppKit
import Speak
import Dictate

// Headless smoke-test modes (CI / dev) come first, so they never spin up UI or
// touch permissions. Each capability owns its own flags; the first to claim the
// args wins. Everything below runs entirely on-device.
let args = CommandLine.arguments

if args.contains("--version") { print("voz 0.1.0"); exit(0) }
if SpeakCLI.handle(args) { exit(0) }    // --speak "text"
if DictateCLI.handle(args) { exit(0) }  // --clean / --transcribe / --engine / --apply / --selftest

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
app.run()
