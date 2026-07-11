import Foundation

/// Resumable HTTP fetch — the engine downloads' honesty layer (ROADMAP 0.4 "engine setup
/// friction"): an interrupted download resumes from where it stopped instead of restarting, and a
/// re-run never re-downloads bytes that are already present and valid.
///
/// Mechanics: bytes stream into `<dest>.part` — never `dest`, so nothing that scans for installed
/// engines can mistake a partial download for a finished file. A re-run finds the partial and asks
/// the server for the remainder (`Range: bytes=<n>-`): a 206 appends, a 200 means the server
/// ignored the range so the file honestly starts over, and a 416 with a full-length partial is
/// verified against the remote size and promoted. Only a complete fetch renames `.part` → dest.
/// Progress callbacks report real bytes on disk (resumed bytes included) over the real total.
public final class ResumableFetch: NSObject, URLSessionDataDelegate {
    public enum Outcome: Equatable {
        case fetched(Int64)          // downloaded (fresh or resumed) and moved into place
        case alreadyComplete(Int64)  // dest already matches the remote size — nothing transferred
    }

    /// What a response means for the partial on disk — pure, unit-tested (SharedTests).
    public enum ResumeAction: Equatable {
        case append(from: Int64) // 206 whose Content-Range starts exactly at our partial
        case restart             // 200 (range ignored), or a 206 we can't trust — start the file over
        case verifyComplete      // 416 with a partial: it may already hold every byte — verify, don't refetch
        case fail(Int)           // anything else is a real failure
    }

    public static func decide(status: Int, partialBytes: Int64, contentRangeStart: Int64?) -> ResumeAction {
        switch status {
        case 206:
            guard partialBytes > 0, let start = contentRangeStart, start == partialBytes else { return .restart }
            return .append(from: partialBytes)
        case 200:
            return .restart
        case 416 where partialBytes > 0:
            return .verifyComplete
        default:
            return .fail(status)
        }
    }

    /// "bytes 102400-262143/262144" → 102400. nil when absent/unparseable (e.g. "bytes */262144").
    public static func contentRangeStart(_ header: String?) -> Int64? {
        guard let h = header, h.hasPrefix("bytes ") else { return nil }
        return Int64(h.dropFirst(6).prefix { $0.isNumber })
    }

    /// "bytes 102400-262143/262144" or "bytes */262144" → 262144. nil when unknown ("…/*").
    public static func contentRangeTotal(_ header: String?) -> Int64? {
        guard let h = header, let slash = h.lastIndex(of: "/") else { return nil }
        return Int64(h[h.index(after: slash)...])
    }

    // Facts about the run, for the --fetch-resume seam's honest log lines.
    public private(set) var startedWithPartial: Int64 = 0
    public private(set) var resumeHonored = false
    public private(set) var partialWasComplete = false

    private var dest: URL!
    private var partial: URL!
    private var handle: FileHandle?
    private var written: Int64 = 0
    private var total: Int64 = -1
    private var failure: String?
    private var verifying = false
    private var onProgress: (Int64, Int64) -> Void = { _, _ in }
    private let done = DispatchSemaphore(value: 0)

    /// Synchronous (every caller is off the main thread or a CLI): fetch `url` into `dest`,
    /// resuming a `<dest>.part` if one exists. Throws with a plain-cause message; the partial is
    /// KEPT on failure so the next run resumes it.
    public func run(_ url: URL, to destURL: URL,
                    onProgress progressCB: @escaping (Int64, Int64) -> Void) throws -> Outcome {
        let fm = FileManager.default
        dest = destURL
        partial = URL(fileURLWithPath: destURL.path + ".part")
        onProgress = progressCB
        try? fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Already present and valid → never re-download. (Unknown remote size: trust the file we
        // have — the caller only asks for URLs whose content is immutable, versioned releases.)
        if let have = size(of: destURL) {
            let remote = headLength(url)
            if remote <= 0 || remote == have { return .alreadyComplete(have) }
            try? fm.removeItem(at: destURL)
        }

        return try attempt(url, allowRetry: true)
    }

    private func attempt(_ url: URL, allowRetry: Bool) throws -> Outcome {
        let fm = FileManager.default
        startedWithPartial = size(of: partial) ?? 0
        if startedWithPartial == 0, !fm.fileExists(atPath: partial.path) {
            fm.createFile(atPath: partial.path, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: partial.path)
        guard handle != nil else { throw Err.bad("can't write \(partial.path)") }
        written = 0; total = -1; failure = nil; verifying = false; resumeHonored = false

        var req = URLRequest(url: url, timeoutInterval: 60)
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding") // ranges are byte-exact — no transcoding
        if startedWithPartial > 0 { req.setValue("bytes=\(startedWithPartial)-", forHTTPHeaderField: "Range") }

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        session.dataTask(with: req).resume()
        done.wait()
        session.invalidateAndCancel()
        try? handle?.close(); handle = nil

        if verifying {
            // 416: our partial claims the whole file. Verify against the remote size and promote —
            // or, if it doesn't match, throw the partial away and fetch fresh (once).
            let remote = headLength(url)
            let have = size(of: partial) ?? 0
            if remote > 0, remote == have {
                partialWasComplete = true
                try promote()
                return .fetched(have)
            }
            try? fm.removeItem(at: partial)
            guard allowRetry else { throw Err.bad("unresumable partial for \(url.lastPathComponent)") }
            return try attempt(url, allowRetry: false)
        }
        if let failure { throw Err.bad(failure) } // partial kept — the next run resumes it
        try promote()
        return .fetched(written)
    }

    /// The only path that creates `dest`: one rename of the complete `.part`.
    private func promote() throws {
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: partial, to: dest)
    }

    private func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.int64Value
    }

    private func headLength(_ url: URL) -> Int64 {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "HEAD"
        let sem = DispatchSemaphore(value: 0)
        var len: Int64 = -1
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            len = resp?.expectedContentLength ?? -1
            sem.signal()
        }.resume()
        sem.wait()
        return len
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200 // non-HTTP (file://) = a plain full body
        let range = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range")
        switch Self.decide(status: status, partialBytes: startedWithPartial,
                           contentRangeStart: Self.contentRangeStart(range)) {
        case .append(let from):
            resumeHonored = true
            written = from
            total = Self.contentRangeTotal(range)
                ?? (response.expectedContentLength > 0 ? from + response.expectedContentLength : -1)
            handle?.seekToEndOfFile()
            onProgress(written, total)
            completionHandler(.allow)
        case .restart:
            written = 0
            total = response.expectedContentLength > 0 ? response.expectedContentLength : -1
            handle?.truncateFile(atOffset: 0)
            onProgress(written, total)
            completionHandler(.allow)
        case .verifyComplete:
            verifying = true
            completionHandler(.cancel)
        case .fail(let s):
            failure = "download failed (HTTP \(s)): \(dataTask.originalRequest?.url?.lastPathComponent ?? "?")"
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handle?.write(data)
        written += Int64(data.count)
        onProgress(written, total)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, failure == nil, !verifying,
           (error as NSError).code != NSURLErrorCancelled {
            failure = error.localizedDescription
        }
        done.signal()
    }

    enum Err: LocalizedError {
        case bad(String)
        var errorDescription: String? { switch self { case .bad(let m): return m } }
    }
}
