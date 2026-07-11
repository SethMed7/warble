import AVFoundation
import Foundation

/// Dictation recovery (ROADMAP 0.3 — product.md §4.10: dictated words are unlosable).
///
/// While the mic is hot the Recorder writes the clip incrementally into `~/.warble/inflight/` — a
/// **crash buffer**, not history: it exists regardless of the Save-recordings setting, and every
/// clean end of a session promotes it (into the history audio store) or deletes it. If warble dies
/// mid-dictation the file survives; the next launch's scan finds it and the menu offers one quiet
/// "Recover Last Dictation" item (never a dialog — product.md §4.5). Recovering transcribes through
/// the normal pipeline and lands the words in History — never an auto-paste (the field the words
/// were meant for is long gone). The buffer is owner-only and bounded (`maxKept` clips, stale ones
/// cleaned), and the dashboard's Clear action removes it with everything else (product.md §4.8).
enum Recovery {
    /// The crash buffer lives beside history so owner-only permissions and Clear cover it.
    static var inflightDir: URL { InsightStore.shared.dir.appendingPathComponent("inflight") }

    /// The bounds (product.md §4.8): at most `maxKept` buffered clips, nothing older than `maxAge`.
    private static let maxKept = 5
    private static let maxAge: TimeInterval = 7 * 24 * 3600
    /// A file this fresh may be a LIVE recording from another warble process (the CLI scanning
    /// while the app records) — never treat it as an orphan.
    private static let minQuietAge: TimeInterval = 5
    /// At or under this size a crash left only a header (or CoreAudio's filler chunk) — no audio.
    private static let headerOnlyBytes = 8192

    /// Where the Recorder writes the next in-flight clip.
    static func newInflightURL() -> URL {
        try? FileManager.default.createDirectory(at: inflightDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return inflightDir.appendingPathComponent(
            "inflight-\(ProcessInfo.processInfo.globallyUniqueString).wav")
    }

    /// Enforce the bounds on the crash buffer, then return the newest orphaned in-flight clip, if
    /// any — the evidence of an unclean exit mid-dictation. Run once at launch (and by the
    /// headless `--recover-scan` seam).
    static func scan() -> URL? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: inflightDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        else { return nil }
        let now = Date()
        var orphans: [(url: URL, mtime: Date)] = []
        for f in files where f.pathExtension == "wav" {
            let vals = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = vals?.contentModificationDate ?? .distantPast
            if (vals?.fileSize ?? 0) <= headerOnlyBytes { try? fm.removeItem(at: f); continue }
            if now.timeIntervalSince(mtime) > maxAge { try? fm.removeItem(at: f); continue }
            if now.timeIntervalSince(mtime) < minQuietAge { continue } // possibly still being written
            orphans.append((f, mtime))
        }
        orphans.sort { $0.mtime > $1.mtime }
        for extra in orphans.dropFirst(maxKept) { try? fm.removeItem(at: extra.url) } // the cap
        return orphans.first?.url
    }

    /// A crash mid-write leaves the WAV's RIFF/data chunk sizes stale (AVAudioFile finalizes them
    /// only on close), so readers see an empty file even though every sample is on disk. Walk the
    /// chunks and set both sizes from the real file length — a no-op on a cleanly closed file.
    static func repairWAVHeader(at url: URL) {
        guard let fh = try? FileHandle(forUpdating: url),
              let fileSize = try? fh.seekToEnd(), fileSize > 44 else { return }
        defer { try? fh.close() }
        func read4(at offset: UInt64) -> Data? {
            try? fh.seek(toOffset: offset)
            guard let d = try? fh.read(upToCount: 4), d.count == 4 else { return nil }
            return d
        }
        func write32(_ value: UInt32, at offset: UInt64) {
            var le = value.littleEndian
            try? fh.seek(toOffset: offset)
            try? fh.write(contentsOf: Data(bytes: &le, count: 4))
        }
        guard read4(at: 0) == Data("RIFF".utf8), read4(at: 8) == Data("WAVE".utf8) else { return }
        var offset: UInt64 = 12
        while offset + 8 <= fileSize {
            guard let id = read4(at: offset), let sizeData = read4(at: offset + 4) else { return }
            let stored = UInt32(littleEndian: sizeData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            if id == Data("data".utf8) { // everything after this header is audio — trust the file, not the field
                let audioBytes = UInt32(clamping: fileSize - (offset + 8))
                if stored != audioBytes {
                    write32(audioBytes, at: offset + 4)
                    write32(UInt32(clamping: fileSize - 8), at: 4)
                }
                return
            }
            offset += 8 + UInt64(stored) + UInt64(stored % 2) // chunks are word-aligned
        }
    }

    /// Clip length straight from the (repaired) file — drives WPM and the recovery copy.
    static func duration(of url: URL) -> TimeInterval {
        guard let f = try? AVAudioFile(forReading: url), f.processingFormat.sampleRate > 0 else { return 0 }
        return Double(f.length) / f.processingFormat.sampleRate
    }

    enum Outcome {
        case recovered(text: String)                    // transcribed + landed in History
        case failedKept(duration: TimeInterval, audio: URL) // engines failed; a FAILED event keeps the audio
        case failedLost                                 // engines failed and the settings forbid keeping audio
        case nothingHeard                               // ran fine, no speech — the buffer is discarded
    }

    /// Transcribe an orphaned in-flight clip through the normal pipeline and land it in History —
    /// never an auto-paste. The orphan is consumed either way: promoted into the history audio
    /// store (per the Save-recordings setting) or deleted. Recovery is user-initiated, so the
    /// secure-field gate doesn't apply (there's no way to know post-crash; the user asked to keep
    /// these words). Completion on the main queue.
    static func recover(_ orphan: URL, completion: @escaping (Outcome) -> Void) {
        repairWAVHeader(at: orphan)
        let clipDuration = duration(of: orphan)
        guard clipDuration > 0.3 else { // damaged beyond audio — nothing recoverable
            try? FileManager.default.removeItem(at: orphan)
            DispatchQueue.main.async { completion(.nothingHeard) }
            return
        }
        let ctx = DictationContext(durationMs: Int(clipDuration * 1000),
                                   engine: Transcribers.activeEngineName(),
                                   appBundleId: nil, appName: nil, secure: false)
        runPipeline(orphan, clipDuration: clipDuration) { outcome in
            defer { try? FileManager.default.removeItem(at: orphan) }
            switch outcome {
            case .text(let cleaned, let raw):
                InsightStore.shared.record(cleaned, raw: raw, ctx: ctx, audioSource: orphan)
                completion(.recovered(text: cleaned))
            case .silence:
                completion(.nothingHeard)
            case .failed:
                if let e = InsightStore.shared.recordFailed(audioSource: orphan, ctx: ctx),
                   let audio = InsightStore.shared.audioURL(for: e) {
                    completion(.failedKept(duration: clipDuration, audio: audio))
                } else {
                    completion(.failedLost)
                }
            }
        }
    }

    enum PipelineOutcome {
        case text(cleaned: String, raw: String)
        case silence
        case failed
    }

    /// "Re-transcribe" on a FAILED history item: run the same pipeline over the kept recording
    /// and, on success, resolve the event in place — History only, never a paste. Completion on
    /// the main queue.
    static func retranscribe(_ event: DictationEvent, completion: @escaping (PipelineOutcome) -> Void) {
        guard let audio = InsightStore.shared.audioURL(for: event) else {
            DispatchQueue.main.async { completion(.failed) }
            return
        }
        // The kept clip is 16 kHz AAC; hand the engines a WAV they can all read (whisper-cli and
        // sherpa can't take m4a). A true temp file — not the crash buffer — removed when done.
        let wav = FileManager.default.temporaryDirectory
            .appendingPathComponent("warble-retranscribe-\(event.id).wav")
        DispatchQueue.global(qos: .userInitiated).async {
            guard AudioConvert.to16kMonoWAV(input: audio, output: wav) else {
                DispatchQueue.main.async { completion(.failed) }
                return
            }
            let clipDuration = max(1, duration(of: wav))
            DispatchQueue.main.async {
                runPipeline(wav, clipDuration: clipDuration) { outcome in
                    try? FileManager.default.removeItem(at: wav)
                    if case .text(let cleaned, let raw) = outcome {
                        InsightStore.shared.resolveFailed(event.id, cleaned: cleaned, raw: raw,
                                                          engine: Transcribers.activeEngineName())
                    }
                    completion(outcome)
                }
            }
        }
    }

    /// The normal post-transcription text pipeline (spell-out → cleanup level → dictionary) —
    /// mirrors DictateController.transcribeAndDeliver minus the UI and the paste. Completion on
    /// the main queue.
    private static func runPipeline(_ audio: URL, clipDuration: TimeInterval,
                                    completion: @escaping (PipelineOutcome) -> Void) {
        Transcribers.run(audio, clipDuration: clipDuration) { outcome in
            switch outcome {
            case .failed: completion(.failed)
            case .silence: completion(.silence)
            case .text(let raw):
                DispatchQueue.global(qos: .utility).async { // LLM / bun cleaner may block
                    let spell = SpellOut.process(raw)
                    let cleaned = Lexicon.shared.apply(Cleaners.best(for: spell.text).clean(spell.text))
                    DispatchQueue.main.async {
                        for rule in spell.learned { Lexicon.shared.learnExplicit(from: rule.from, to: rule.to) }
                        completion(.text(cleaned: cleaned.isEmpty ? raw : cleaned, raw: raw))
                    }
                }
            }
        }
    }
}
