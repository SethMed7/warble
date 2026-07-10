import Foundation
import Shared

/// Manages warble's warm Parakeet ASR server (core/asr-server.py in a venv, installed by
/// scripts/setup-asr.sh). It keeps the model loaded so each clip transcribes in ~0.08s over
/// loopback HTTP instead of the ~1.5s a cold sherpa CLI spawn costs — same model, same quality.
///
/// Optional + graceful: if the venv/script/model aren't present, everything no-ops and warble uses the
/// cold transcription chain. A server left running from a previous warble session is detected (health
/// check) and reused, so warmth persists across restarts.
final class WarmASR {
    static let shared = WarmASR()

    private let port = ProcessInfo.processInfo.environment["WARBLE_ASR_PORT"] ?? "8765"
    private var server: Process?
    private let lock = NSLock()

    private static func home() -> String { FileManager.default.homeDirectoryForCurrentUser.path }
    static func venvPython() -> String? { Subprocess.firstExecutable(["\(home())/.warble/asr-venv/bin/python3"]) }
    static func scriptPath() -> String? {
        let p = "\(home())/.warble/asr-server.py"
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }
    /// Installed = venv python + the server script + the Parakeet model all present.
    static func isInstalled() -> Bool {
        venvPython() != nil && scriptPath() != nil && SherpaTranscriber.modelDir() != nil
    }

    private var baseURL: String { "http://127.0.0.1:\(port)" }

    /// Start the server if installed and not already healthy (reusing any prior instance). Idempotent;
    /// the model loads in the child (~1.1s). Call OFF the main thread.
    func ensureRunning() {
        // .foreign = the port is squatted by an unrelated local service: our spawn couldn't bind and
        // /health will never say ok — skip the warm path instead of burning the wait on every clip.
        guard Self.isInstalled(), LoopbackHTTP.health(baseURL) == .down else { return }
        lock.lock(); defer { lock.unlock() }
        if let s = server, s.isRunning { return }
        if isHealthy() { return } // a prior session's server is already up — reuse it
        guard let py = Self.venvPython(), let script = Self.scriptPath() else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        p.arguments = [script]
        var env = ProcessInfo.processInfo.environment
        env["WARBLE_ASR_PORT"] = port
        if let model = SherpaTranscriber.modelDir() { env["WARBLE_PARAKEET_MODEL"] = model }
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        server = (try? p.run()) != nil ? p : nil
    }

    func isHealthy() -> Bool { LoopbackHTTP.health(baseURL) == .ok }

    /// Transcribe a 16k-mono WAV via the warm server. nil if unavailable/failed → caller falls back
    /// to the cold chain. Call OFF the main thread. `timeout` scales with clip length, so a long
    /// dictation isn't cut off at a fixed cap and needlessly bumped to the slower cold engine.
    func transcribe(wav16kPath: String, timeout: TimeInterval) -> String? {
        guard Self.isInstalled() else { return nil }
        ensureRunning()
        guard waitHealthy(timeout: 8) else { return nil } // first call waits out the one-time model load
        guard let body = try? JSONSerialization.data(withJSONObject: ["path": wav16kPath]) else { return nil }
        guard let d = LoopbackHTTP.postJSON("\(baseURL)/transcribe", body: body, timeout: max(15, timeout)),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let text = obj["text"] as? String else { return nil }
        return text
    }

    func shutdown() {
        lock.lock(); defer { lock.unlock() }
        if let s = server, s.isRunning { s.terminate() }
        server = nil
    }

    private func waitHealthy(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            switch LoopbackHTTP.health(baseURL) {
            case .ok: return true
            case .foreign: return false // squatted port — it will never become ours
            case .down: usleep(200_000)
            }
        } while Date() < deadline
        return false
    }
}
