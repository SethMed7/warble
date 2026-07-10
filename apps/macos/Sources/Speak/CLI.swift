import AppKit

/// Headless smoke tests for the read-aloud pipeline:
///   `warble --speak "text"`     — exercises the TTS path (Kokoro if installed, else macOS voice).
///   `warble --pronounce "text"` — applies your shared-dictionary pronunciations (no audio), the
///                              read-aloud twin of `--apply`.
public enum SpeakCLI {
    /// Returns true if it handled the args (the caller should then exit).
    public static func handle(_ args: [String]) -> Bool {
        if let i = args.firstIndex(of: "--pronounce"), i + 1 < args.count {
            print(Pronouncer.shared.apply(args[i + 1]))
            return true
        }
        guard let i = args.firstIndex(of: "--speak"), i + 1 < args.count else { return false }
        let done = DispatchSemaphore(value: 0)
        Speaker.shared.onQueueDrained = { done.signal() }
        Speaker.shared.speakNow(args[i + 1])
        _ = done.wait(timeout: .now() + 120)
        return true
    }
}
