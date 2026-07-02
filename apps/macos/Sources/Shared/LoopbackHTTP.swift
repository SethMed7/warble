import Foundation

/// Synchronous HTTP for the warm-server loopback protocols (ports: 8765 ASR, 8766 LLM, 8767 TTS).
/// Every caller is off the main thread and intentionally blocking — the warm request IS the work —
/// so a semaphore bridge over URLSession replaces the curl subprocess each request used to spawn
/// (a fork/exec per health probe and per dictation, plus a runtime dependency on a curl binary).
/// nil on ANY failure (refused, timeout, non-2xx) so callers fall back to their cold chains.
public enum LoopbackHTTP {
    /// One shared session: ephemeral (nothing cached or persisted) with proxies hard-disabled —
    /// loopback traffic must NEVER traverse a system proxy (a configured proxy would receive the
    /// request bytes, breaking both the connection and the 100%-on-device privacy promise).
    /// waitsForConnectivity=false so a down server fails immediately instead of queueing.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    public static func get(_ url: String, timeout: TimeInterval) -> Data? {
        guard var req = request(url, timeout: timeout) else { return nil }
        req.httpMethod = "GET"
        return perform(req, timeout: timeout)
    }

    /// A warm-server port can be squatted by an unrelated local service, and every voz server answers
    /// /health with {"ok": true} — so "responded but not ours" is its own signal, distinct from "no
    /// response". `.foreign` will never become healthy (our spawn couldn't even bind), so callers bail
    /// to their cold chains at once instead of polling the full model-load wait on every request.
    public enum ServerHealth { case ok, foreign, down }

    public static func health(_ baseURL: String, timeout: TimeInterval = 1) -> ServerHealth {
        guard var req = request("\(baseURL)/health", timeout: timeout) else { return .down }
        req.httpMethod = "GET"
        guard let r = response(req, timeout: timeout) else { return .down }
        guard r.status == 200, let s = String(data: r.body, encoding: .utf8), s.contains("\"ok\"") else {
            return .foreign
        }
        return .ok
    }

    public static func postJSON(_ url: String, body: Data, timeout: TimeInterval) -> Data? {
        guard var req = request(url, timeout: timeout) else { return nil }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return perform(req, timeout: timeout)
    }

    private static func request(_ url: String, timeout: TimeInterval) -> URLRequest? {
        guard let u = URL(string: url) else { return nil }
        return URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    }

    private static func perform(_ req: URLRequest, timeout: TimeInterval) -> Data? {
        guard let r = response(req, timeout: timeout), (200..<300).contains(r.status) else { return nil }
        return r.body
    }

    private static func response(_ req: URLRequest, timeout: TimeInterval) -> (status: Int, body: Data)? {
        var result: (status: Int, body: Data)?
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: req) { data, resp, _ in
            if let http = resp as? HTTPURLResponse { result = (http.statusCode, data ?? Data()) }
            done.signal()
        }
        task.resume()
        // URLSession enforces `timeout` itself; the margin here only guards a wedged task so a
        // blocked caller can never hang forever.
        if done.wait(timeout: .now() + timeout + 5) != .success { task.cancel(); return nil }
        return result
    }
}
