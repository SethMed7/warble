import Foundation
import Shared

/// Manages warble's warm MLX LLM polish server (core/llm-server.py in a venv, installed by
/// scripts/setup-cleaner.sh). Keeps a small instruct model (Qwen2.5-1.5B-Instruct) loaded so each
/// polish runs in well under a second over loopback HTTP instead of paying a per-clip model reload —
/// the same warm-server pattern as WarmASR. Apple Silicon only (MLX).
///
/// Optional + graceful: if the venv/script/model aren't present, everything no-ops and the cleaner
/// chain falls back. A server left running from a previous warble session is detected (health check) and
/// reused, so warmth persists across restarts. PRIVACY: spawned with HF_HUB_OFFLINE=1, so it can never
/// reach the network at dictation time — only the weights you approved at setup are ever used.
final class WarmLLM {
    static let shared = WarmLLM()

    private let port = ProcessInfo.processInfo.environment["WARBLE_LLM_PORT"] ?? "8766"
    private var server: Process?
    private let lock = NSLock()

    private static func home() -> String { FileManager.default.homeDirectoryForCurrentUser.path }
    static func venvPython() -> String? { Subprocess.firstExecutable(["\(home())/.warble/llm-venv/bin/python3"]) }
    static func scriptPath() -> String? {
        let p = "\(home())/.warble/llm-server.py"
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }
    /// A marker dropped by setup-cleaner.sh once the model is downloaded with your consent. The server
    /// runs offline, so without cached weights its first load would fail — gating on this keeps the
    /// warm path dark until the download actually happened.
    static func modelReady() -> Bool {
        FileManager.default.fileExists(atPath: "\(home())/.warble/llm-model")
    }
    /// Installed = venv python + the server script + a consented model download.
    static func isInstalled() -> Bool {
        venvPython() != nil && scriptPath() != nil && modelReady()
    }

    private var baseURL: String { "http://127.0.0.1:\(port)" }

    /// Start the server if installed and not already healthy (reusing any prior instance). Idempotent;
    /// the model loads in the child (~1-2s). Call OFF the main thread.
    func ensureRunning() {
        // .foreign = the port is squatted by an unrelated local service: our spawn couldn't bind and
        // /health will never say ok — skip the warm path instead of burning the wait on every polish.
        guard Self.isInstalled(), LoopbackHTTP.health(baseURL) == .down else { return }
        lock.lock(); defer { lock.unlock() }
        if let s = server, s.isRunning { return }
        if isHealthy() { return } // a prior session's server is already up — reuse it
        guard let py = Self.venvPython(), let script = Self.scriptPath() else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        p.arguments = [script]
        var env = ProcessInfo.processInfo.environment
        env["WARBLE_LLM_PORT"] = port
        env["HF_HUB_OFFLINE"] = "1"            // never reach the network at dictation time
        env["TOKENIZERS_PARALLELISM"] = "false"
        // The marker holds the model to load: a local dir (native Setup install → fully offline) or an
        // HF repo id (shell install → from the HF cache). An explicit env var still wins.
        if let raw = try? String(contentsOfFile: "\(Self.home())/.warble/llm-model", encoding: .utf8) {
            let m = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !m.isEmpty { env["WARBLE_LLM_MODEL"] = m }
        }
        if let m = ProcessInfo.processInfo.environment["WARBLE_LLM_MODEL"]
                ?? ProcessInfo.processInfo.environment["VOZ_LLM_MODEL"], // rename-era fallback (voz ≤ 0.1.8)
           !m.isEmpty { env["WARBLE_LLM_MODEL"] = m }
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        server = (try? p.run()) != nil ? p : nil
    }

    func isHealthy() -> Bool { LoopbackHTTP.health(baseURL) == .ok }

    /// Polish `text` with `system` as the instruction, via the warm server. nil if unavailable/failed
    /// → caller falls back to the deterministic cleaner. Call OFF the main thread. `timeout` bounds the
    /// request; the first call also waits out the one-time model load.
    func clean(system: String, text: String, timeout: TimeInterval) -> String? {
        // Polish output is ~the input length, so cap generation near it (≈chars/3 tokens + headroom)
        // instead of a flat 1024 — the model can't ramble, which is the dominant cost on long dictations.
        let maxTokens = max(96, min(1024, text.count / 3 + 64))
        return post("/clean", system: system, text: text, maxTokens: maxTokens, timeout: timeout)
    }

    /// Generic generation via the warm server's `/generate` (no dictation accept() guard) — for the
    /// Insights AI summary, which phrases *aggregate numbers* rather than reformatting a transcript.
    /// Same warm model/venv as `clean`. nil if unavailable/failed → caller falls back to a deterministic
    /// template. Call OFF the main thread. `timeout` bounds the request; the first call also waits out
    /// the one-time model load.
    func generate(system: String, text: String, timeout: TimeInterval) -> String? {
        // A summary is a few sentences; cap generation tight so the small model can't ramble.
        return post("/generate", system: system, text: text, maxTokens: 256, timeout: timeout)
    }

    /// The shared request plumbing for `clean`/`generate`: gate on install, warm the server, POST the
    /// `{system,text,max_tokens}` body to `path`, and pull `text` back out. nil on any failure.
    private func post(_ path: String, system: String, text: String, maxTokens: Int, timeout: TimeInterval) -> String? {
        guard Self.isInstalled() else { return nil }
        ensureRunning()
        guard waitHealthy(timeout: 15) else { return nil } // first call waits out the one-time model load
        let body: [String: Any] = ["system": system, "text": text, "max_tokens": maxTokens]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        guard let d = LoopbackHTTP.postJSON("\(baseURL)\(path)", body: data, timeout: timeout),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let out = obj["text"] as? String else { return nil }
        return out
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
