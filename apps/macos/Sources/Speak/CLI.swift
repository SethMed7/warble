import AppKit

/// Headless smoke test for the read-aloud pipeline: `voz --speak "text"`.
/// Exercises the TTS path (Kokoro if installed, else the macOS voice) with no UI.
public enum SpeakCLI {
    /// Returns true if it handled the args (the caller should then exit).
    public static func handle(_ args: [String]) -> Bool {
        guard let i = args.firstIndex(of: "--speak"), i + 1 < args.count else { return false }
        let done = DispatchSemaphore(value: 0)
        Speaker.shared.onQueueDrained = { done.signal() }
        Speaker.shared.speakNow(args[i + 1])
        _ = done.wait(timeout: .now() + 120)
        return true
    }
}
