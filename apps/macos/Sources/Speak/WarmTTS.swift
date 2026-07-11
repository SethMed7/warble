import Foundation
import Shared

/// Manages warble's warm Kokoro TTS server (core/say-server.ts, installed beside say.ts by
/// scripts/setup-kokoro-server.sh). It keeps the model loaded so each read skips the ~1-2s per-spawn
/// reload the one-shot say.ts pays — same model + voices, just resident. Binds 127.0.0.1 ONLY.
///
/// Optional + graceful: if bun / the script / kokoro-js aren't present, everything no-ops and warble
/// uses the cold per-spawn say.ts path (KokoroEngine falls back). A server left running from a prior
/// session is detected (health check) and reused, so warmth persists across restarts. `ready` is a
/// cheap cached flag the audio engine reads on the main thread to pick warm-vs-cold without blocking.
final class WarmTTS {
    static let shared = WarmTTS()

    // Warm-server port map: 8765 ASR, 8766 LLM, 8767 TTS. TTS must NOT share the LLM's 8766 — with
    // both installed one can't bind, and /health would false-positive against the LLM server (both
    // answer {"ok": true}). The port is always passed to the server we spawn, so the pair stays
    // consistent even if say-server.ts's own default drifts.
    let port = ProcessInfo.processInfo.environment["WARBLE_TTS_PORT"] ?? "8767"
    private var server: Process?
    private let lock = NSLock()

    /// Cached health, updated by prewarm() off the main thread; read cheaply on main by KokoroEngine.
    private(set) var ready = false
    private var lastHealthyAt = Date.distantPast  // skip the probe on rapid re-arms when recently healthy
    private var shuttingDown = false              // set at quit so a racing prewarm can't re-spawn an orphan

    var baseURL: String { "http://127.0.0.1:\(port)" }

    private static func home() -> String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// Where say-server.ts + kokoro-js live: ~/.warble/kokoro (current) else ~/.leelo (legacy) — matches
    /// KokoroEngine.helperDir so the server runs with kokoro-js resolvable.
    static func helperDir() -> String {
        let home = home()
        let warble = "\(home)/.warble/kokoro", legacy = "\(home)/.leelo"
        let fm = FileManager.default
        if fm.fileExists(atPath: "\(warble)/node_modules/kokoro-js") { return warble }
        if fm.fileExists(atPath: "\(legacy)/node_modules/kokoro-js") { return legacy }
        return warble
    }
    static func scriptPath() -> String? {
        let p = "\(helperDir())/say-server.ts"
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }
    static func bunPath() -> String? {
        firstExecutable(["\(home())/.bun/bin/bun", "/opt/homebrew/bin/bun", "/usr/local/bin/bun"])
    }
    /// Installed = bun + the server script + kokoro-js all present.
    static func isInstalled() -> Bool {
        bunPath() != nil && scriptPath() != nil
            && FileManager.default.fileExists(atPath: "\(helperDir())/node_modules/kokoro-js")
    }

    /// Still curl-based: Speaker's /render request streams "<path>\t<chunk>" lines as they render,
    /// and LoopbackHTTP is whole-body synchronous — unsuitable for a live chunk stream.
    static func curlPath() -> String {
        firstExecutable(["/usr/bin/curl", "/opt/homebrew/bin/curl"]) ?? "/usr/bin/curl"
    }

    // Subprocess lives in the Dictate module, and Speak shouldn't depend on it, so WarmTTS carries
    // its own tiny copy.
    private static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func isHealthy() -> Bool { LoopbackHTTP.health(baseURL) == .ok }

    /// Start the server if installed and not already healthy (reusing any prior instance), then poll
    /// until it answers /health (the one-time model load is ~1-2s). Idempotent. Call OFF the main
    /// thread. Updates `ready` so the audio engine can pick the warm path on the main thread.
    func prewarm() {
        guard Self.isInstalled() else { ready = false; return }
        if ready, Date().timeIntervalSince(lastHealthyAt) < 30 { return } // trust the cache — no probe
        switch LoopbackHTTP.health(baseURL) {
        case .ok: ready = true; lastHealthyAt = Date(); return // a prior session's server is up — reuse it
        case .foreign: ready = false; return // squatted by another local service — a spawn couldn't bind
        case .down: break
        }
        lock.lock()
        if !shuttingDown, server == nil || server?.isRunning != true, !isHealthy(),
           let bun = Self.bunPath(), let script = Self.scriptPath() {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bun)
            p.arguments = ["run", script]
            p.currentDirectoryURL = URL(fileURLWithPath: Self.helperDir())
            var env = ProcessInfo.processInfo.environment
            env["WARBLE_TTS_PORT"] = port
            // Honor an explicit "warble only" store choice — without this the script's shared-store
            // default would migrate the legacy cache into ~/.memex against the user's pick.
            if let cache = AIStore.kokoroCacheOverride() { env["WARBLE_KOKORO_CACHE"] = cache }
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            server = (try? p.run()) != nil ? p : nil
            if server == nil { Log.speak.error("warm TTS server failed to spawn") }
        }
        lock.unlock()
        ready = waitHealthy(timeout: 12)
        if ready { lastHealthyAt = Date() }
    }

    /// A warm request just failed — re-verify health on the next read rather than trusting the cache.
    func markStale() { ready = false }

    func shutdown() {
        lock.lock(); defer { lock.unlock() }
        shuttingDown = true   // so a prewarm racing past this can't re-spawn an orphan server
        if let s = server, s.isRunning { s.terminate() }
        server = nil
        ready = false
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
