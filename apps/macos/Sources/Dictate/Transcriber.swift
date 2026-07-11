import AVFoundation
import Foundation
import Speech
import Shared

/// Transcribes a recorded WAV in ONE pass (file/batch mode) — the opposite of
/// the old streaming recognizer. File mode has none of streaming's failure
/// modes: no endpointer, no 30s timeout, no 1-minute cap, no isFinal-on-device
/// hang, and crucially no pause-drop. Pluggable like the Cleaner protocol.
protocol Transcriber {
    /// Transcribe `wav`, calling completion on the main queue with the text — nil when the
    /// ENGINE failed (spawn error, non-zero exit, timeout, denied auth), "" when it ran fine and
    /// heard nothing. The distinction is what lets the chain name "transcription failed" vs
    /// "nothing heard". Bounded by `timeout` so a wedged engine can never hang the paste path.
    func transcribe(_ wav: URL, timeout: TimeInterval, completion: @escaping (String?) -> Void)
}

enum Transcribers {
    /// What a run of the whole chain concluded, so the caller can name the cause.
    enum Outcome {
        case text(String) // a transcript (non-empty, post-hallucination-filter)
        case silence      // at least one engine ran fine and heard nothing — the clip is empty
        case failed       // EVERY engine errored — the audio is still good; the caller keeps it
    }

    /// Run the best available engine, falling through to the next on any empty/failed
    /// result over the SAME WAV (mirrors the cleaner chain's fall-through) — so a 30-second hold
    /// is never silently lost. Priority: Parakeet (sherpa-onnx, NVIDIA, best accuracy +
    /// no silence-hallucination) → whisper.cpp → Apple on-device (the zero-setup floor).
    /// Every result passes the anti-hallucination filter.
    static func run(_ wav: URL, clipDuration: TimeInterval, completion: @escaping (Outcome) -> Void) {
        if Fault.isActive(.transcribeFail) { DispatchQueue.main.async { completion(.failed) }; return }
        if Fault.isActive(.engineWarming) { return } // never completes → the processing watchdog names the warm-up
        let timeout = max(15, clipDuration * 2 + 8)
        #if DEBUG
        if let forced = forcedChain() { // bench seam — see forcedChain()
            tryChain(forced, 0, wav, timeout, sawEmpty: false, completion)
            return
        }
        #endif
        var chain: [Transcriber] = []
        if !Fault.isActive(.engineMissing) { // debug-only: pretend no premium engine is installed
            if WarmSherpaTranscriber.isAvailable() { chain.append(WarmSherpaTranscriber()) } // warm Parakeet (~0.08s)
            if SherpaTranscriber.isAvailable() { chain.append(SherpaTranscriber()) }          // cold Parakeet fallback
            if WhisperTranscriber.isAvailable() { chain.append(WhisperTranscriber()) }
        }
        chain.append(AppleFileTranscriber()) // always present: the install-free baseline
        tryChain(chain, 0, wav, timeout, sawEmpty: false, completion)
    }

    private static func tryChain(_ chain: [Transcriber], _ i: Int, _ wav: URL, _ timeout: TimeInterval,
                                 sawEmpty: Bool, _ completion: @escaping (Outcome) -> Void) {
        guard i < chain.count else { completion(sawEmpty ? .silence : .failed); return }
        let engine = chain[i]
        engine.transcribe(wav, timeout: timeout) { text in
            _ = engine // retain the instance through its async call
            guard let text else { // engine errored → next engine, same WAV
                Log.dictate.error("engine \(String(describing: type(of: engine)), privacy: .public) failed — falling through")
                tryChain(chain, i + 1, wav, timeout, sawEmpty: sawEmpty, completion)
                return
            }
            let cleaned = Hallucination.filter(text)
            if !cleaned.isEmpty { completion(.text(cleaned)); return }
            tryChain(chain, i + 1, wav, timeout, sawEmpty: true, completion) // ran, heard nothing → next engine
        }
    }

    /// User-facing name of the engine a dictation would use right now — the single source of
    /// truth for the priority order, shown in the menu and the --engine flag.
    static func activeEngineName() -> String {
        #if DEBUG
        if let forced = forcedEngineName() { return forced } // bench seam, mirrors run()
        #endif
        if Fault.isActive(.engineMissing) { return "Apple Speech" } // debug-only, mirrors run()
        if WarmSherpaTranscriber.isAvailable() { return "Parakeet (warm)" }
        if SherpaTranscriber.isAvailable() { return "Parakeet" }
        if WhisperTranscriber.isAvailable() { return "whisper.cpp" }
        return "Apple Speech"
    }

    #if DEBUG
    /// Bench seam (scripts/bench; DEBUG builds only, like Fault): WARBLE_FORCE_ENGINE pins the
    /// chain to exactly ONE engine — no Apple floor, no fall-through — so a per-engine benchmark
    /// number is that engine's alone. A forced engine that isn't installed yields an empty chain
    /// (→ .failed), never a silent fallback that would mislabel the number. `stub` is the
    /// engine-free fixed-utterance engine the regression smoke runs on any machine.
    private static var forcedEngine: String? { ProcessInfo.processInfo.environment["WARBLE_FORCE_ENGINE"] }

    private static func forcedChain() -> [Transcriber]? {
        switch forcedEngine {
        case "parakeet-warm": return WarmSherpaTranscriber.isAvailable() ? [WarmSherpaTranscriber()] : []
        case "parakeet":      return SherpaTranscriber.isAvailable() ? [SherpaTranscriber()] : []
        case "whisper":       return WhisperTranscriber.isAvailable() ? [WhisperTranscriber()] : []
        case "apple":         return [AppleFileTranscriber()]
        case "stub":          return [StubTranscriber()]
        default:              return nil
        }
    }

    private static func forcedEngineName() -> String? {
        switch forcedEngine {
        case "parakeet-warm": return "Parakeet (warm)"
        case "parakeet":      return "Parakeet"
        case "whisper":       return "whisper.cpp"
        case "apple":         return "Apple Speech"
        case "stub":          return "stub"
        default:              return nil
        }
    }
    #endif
}

// MARK: - in-process audio conversion (replaces the per-clip afconvert spawn)

/// One AVAudioConverter pass, file to file — handles whatever rate/channel count the input
/// device produced. Serves both the transcribers (16 kHz mono int16 WAV for sherpa/WarmASR)
/// and the history store (16 kHz mono AAC, ~25x smaller than the raw float WAV). Returns
/// false on any error so callers keep the exact fall-through they had when afconvert failed.
enum AudioConvert {
    static func to16kMonoWAV(input: URL, output: URL) -> Bool {
        guard let pcm16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                        channels: 1, interleaved: true) else { return false }
        return transcode(input: input, output: output) {
            try AVAudioFile(forWriting: output, settings: pcm16.settings,
                            commonFormat: .pcmFormatInt16, interleaved: true)
        }
    }

    static func to16kMonoAAC(input: URL, output: URL) -> Bool {
        // 32 kbps AAC is transparent for 16 kHz mono speech; AVAudioFile does the encode
        // from the PCM buffers the converter hands it.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        return transcode(input: input, output: output) {
            try AVAudioFile(forWriting: output, settings: settings)
        }
    }

    private struct ConvertFailed: Error {}

    private static func transcode(input: URL, output: URL, makeOutput: () throws -> AVAudioFile) -> Bool {
        do {
            let inFile = try AVAudioFile(forReading: input)
            let outFile = try makeOutput()
            let src = inFile.processingFormat
            let dst = outFile.processingFormat
            guard let converter = AVAudioConverter(from: src, to: dst),
                  let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: 8192),
                  let outBuf = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity:
                      AVAudioFrameCount((8192 * dst.sampleRate / src.sampleRate).rounded(.up)) + 512)
            else { throw ConvertFailed() }

            var readError: Error?
            // The returned buffer is only refilled inside this block, satisfying the converter's
            // "don't touch it until the next pull" contract. endOfStream is terminal for the
            // converter, so no drained flag is needed.
            let pull: AVAudioConverterInputBlock = { _, status in
                // AVAudioFile.read(into:) THROWS at EOF instead of returning an empty buffer
                // (verified) — check the position, don't read past the end.
                if inFile.framePosition >= inFile.length { status.pointee = .endOfStream; return nil }
                do { try inFile.read(into: inBuf) } catch {
                    readError = error; status.pointee = .endOfStream; return nil
                }
                if inBuf.frameLength == 0 { status.pointee = .endOfStream; return nil }
                status.pointee = .haveData
                return inBuf
            }
            while true {
                outBuf.frameLength = 0
                var err: NSError?
                let status = converter.convert(to: outBuf, error: &err, withInputFrom: pull)
                if let readError { throw readError }
                if status == .error { throw err ?? ConvertFailed() }
                if outBuf.frameLength > 0 { try outFile.write(from: outBuf) }
                if status == .endOfStream { break }
            }
            return true
        } catch {
            try? FileManager.default.removeItem(at: output) // never leave a truncated file behind
            return false
        }
    }
}

// MARK: - Warm Parakeet (sherpa-onnx kept loaded via WarmASR — ~0.08s/clip vs ~1.5s cold)

/// Transcribes via warble's warm ASR server: convert to 16k mono in-process, then hand the path to
/// WarmASR (loopback HTTP). Same Parakeet model as SherpaTranscriber, just never reloaded. Returns
/// nil on any failure so the chain falls through to the cold engines.
final class WarmSherpaTranscriber: Transcriber {
    static func isAvailable() -> Bool { WarmASR.isInstalled() }

    func transcribe(_ wav: URL, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let wav16 = wav.deletingPathExtension().appendingPathExtension("warm16k.wav")
            defer { try? FileManager.default.removeItem(at: wav16) }
            guard AudioConvert.to16kMonoWAV(input: wav, output: wav16) else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            let text = WarmASR.shared.transcribe(wav16kPath: wav16.path, timeout: timeout)
            DispatchQueue.main.async { completion(text) }
        }
    }
}

// MARK: - Parakeet via sherpa-onnx (preferred: NVIDIA, non-OpenAI, no silence-hallucination)

/// Shells out to the `sherpa-onnx-offline` binary running NVIDIA Parakeet (CC-BY-4.0). Best
/// accuracy in this class and — because Parakeet was trained on non-speech audio — it returns
/// nothing on silence instead of inventing phantom text. sherpa needs 16-bit mono PCM, so we
/// convert in-process first (AudioConvert). ~1.2s/clip; the model loads per spawn (WarmASR is
/// the warm path). Detected on disk like whisper, so the base app stays a tiny build.
final class SherpaTranscriber: Transcriber {
    private static func matches(_ pattern: String) -> [String] {
        var g = glob_t()
        defer { globfree(&g) }
        guard pattern.withCString({ glob($0, 0, nil, &g) }) == 0 else { return [] }
        return (0..<Int(g.gl_pathc)).compactMap { g.gl_pathv[$0].map { String(cString: $0) } }
    }

    static func binaryPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            ProcessInfo.processInfo.environment["WARBLE_SHERPA_BIN"],
            ProcessInfo.processInfo.environment["DICTADO_SHERPA_BIN"],
            "\(home)/.warble/sherpa/bin/sherpa-onnx-offline",
            "\(home)/.dictado/sherpa/bin/sherpa-onnx-offline",
            "/opt/homebrew/bin/sherpa-onnx-offline",
            "/usr/local/bin/sherpa-onnx-offline",
            "\(home)/.local/bin/sherpa-onnx-offline",
        ].compactMap { $0 }
        candidates += matches("\(AIStore.sharedModels)/*/bin/sherpa-onnx-offline") // shared memex store (preferred)
        candidates += matches("\(home)/.cache/sherpa/*/bin/sherpa-onnx-offline")    // legacy warble-only cache
        return Subprocess.firstExecutable(candidates)
    }

    /// A Parakeet (or other transducer) model dir holding tokens.txt + the three onnx files.
    static func modelDir() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            ProcessInfo.processInfo.environment["WARBLE_PARAKEET_MODEL"],
            ProcessInfo.processInfo.environment["DICTADO_PARAKEET_MODEL"],
            "\(home)/.warble/sherpa/model",
            "\(home)/.dictado/sherpa/model",
        ].compactMap { $0 }
        candidates += matches("\(AIStore.sharedModels)/*parakeet*") // shared memex store (preferred)
        candidates += matches("\(home)/.cache/sherpa/*parakeet*")   // legacy warble-only cache
        let fm = FileManager.default
        return candidates.first {
            fm.fileExists(atPath: "\($0)/tokens.txt") && fm.fileExists(atPath: "\($0)/encoder.int8.onnx")
        }
    }

    static func isAvailable() -> Bool { binaryPath() != nil && modelDir() != nil }

    func transcribe(_ wav: URL, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        guard let bin = Self.binaryPath(), let model = Self.modelDir() else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // sherpa needs single-channel 16-bit PCM.
            let wav16 = wav.deletingPathExtension().appendingPathExtension("16k.wav")
            defer { try? FileManager.default.removeItem(at: wav16) }
            guard AudioConvert.to16kMonoWAV(input: wav, output: wav16) else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            // No --model-type: auto-detect handles Parakeet TDT (the `transducer` value rejects it).
            let args = [
                "--tokens=\(model)/tokens.txt",
                "--encoder=\(model)/encoder.int8.onnx",
                "--decoder=\(model)/decoder.int8.onnx",
                "--joiner=\(model)/joiner.int8.onnx",
                "--num-threads=4",
                wav16.path,
            ]
            var text: String? // nil = the spawn failed/timed out/exited non-zero
            if let r = Subprocess.run(bin, args, timeout: timeout), r.status == 0 { text = Self.parseText(r.stdout) }
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// sherpa-onnx-offline prints a JSON object with a "text" field to stdout.
    private static func parseText(_ data: Data) -> String {
        guard let s = String(data: data, encoding: .utf8),
              let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end,
              let jd = String(s[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
              let text = obj["text"] as? String else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - whisper.cpp (fallback: best accuracy, unlimited length, fully local)

/// Spawns whisper-cli over the recorded WAV. NO --vad (it SIGABRTs on Metal
/// here and needs a separate model); the Recorder already controls clip
/// boundaries. Silence-hallucination is handled by the RMS gate upstream +
/// Hallucination.filter downstream, NOT by flags (verified: -sns alone doesn't
/// suppress it).
final class WhisperTranscriber: Transcriber {
    private static let binaries = ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli",
                                   FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/whisper-cli").path]

    static func binaryPath() -> String? { Subprocess.firstExecutable(binaries) }

    /// A real ggml whisper model: ~/.cache/whisper/ggml-small.en.bin, or a model
    /// bundled in the app's Resources. Verifies the "ggml" magic so a stray
    /// PyTorch checkpoint (e.g. base.pt) is never handed to whisper-cli.
    static func modelPath() -> String? {
        var candidates = [FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/whisper/ggml-small.en.bin").path]
        for name in ["ggml-small.en", "ggml-base.en"] {
            if let p = Bundle.main.path(forResource: name, ofType: "bin") { candidates.append(p) }
        }
        return candidates.first { isGGML($0) }
    }

    private static func isGGML(_ path: String) -> Bool {
        guard let h = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? h.close() }
        guard let magic = try? h.read(upToCount: 4), magic.count == 4 else { return false }
        return Array(magic) == [0x67, 0x67, 0x6D, 0x6C] // "ggml"
    }

    static func isAvailable() -> Bool { binaryPath() != nil && modelPath() != nil }

    func transcribe(_ wav: URL, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        guard let bin = Self.binaryPath(), let model = Self.modelPath() else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let args = ["-m", model, "-f", wav.path, "-nt", "-np", "-l", "en", "-sns"]
            var text: String? // nil = the spawn failed/timed out/exited non-zero
            if let r = Subprocess.run(bin, args, timeout: timeout), r.status == 0 {
                text = String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            DispatchQueue.main.async { completion(text) }
        }
    }
}

// MARK: - Apple on-device file recognizer (zero-setup fallback)

/// SFSpeechURLRecognitionRequest in FILE mode with requiresOnDeviceRecognition
/// — the guaranteed install-free path when whisper isn't present. Never the
/// server: if the locale can't do on-device, it refuses (returns empty).
final class AppleFileTranscriber: Transcriber {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var resolved = false
    private let lock = NSLock() // the recognition callback and the timeout race to finish exactly once

    func transcribe(_ wav: URL, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        ensureAuth { [weak self] ok in
            guard let self else { completion(nil); return }
            guard ok, let recognizer = self.recognizer, recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition else { completion(nil); return }

            let request = SFSpeechURLRecognitionRequest(url: wav)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false

            let finish: (String?) -> Void = { text in
                self.lock.lock()
                if self.resolved { self.lock.unlock(); return }
                self.resolved = true
                self.lock.unlock()
                self.task?.cancel(); self.task = nil
                DispatchQueue.main.async { completion(text) }
            }

            self.task = recognizer.recognitionTask(with: request) { result, error in
                // `latest` is written here (Speech's queue) and read by the timeout (main) — guard both.
                if let result {
                    self.lock.lock(); self.latest = result.bestTranscription.formattedString; let snap = self.latest; self.lock.unlock()
                    if result.isFinal { finish(snap) }
                }
                // Errored (or timed out below) with no partial text = the ENGINE failed → nil;
                // with a partial, the words win — deliver what it got.
                if error != nil { self.lock.lock(); let snap = self.latest; self.lock.unlock(); finish(snap.isEmpty ? nil : snap) }
            }
            // Bound it: on-device file recognition is usually quick, but never hang the paste path.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                self.lock.lock(); let snap = self.latest; self.lock.unlock(); finish(snap.isEmpty ? nil : snap)
            }
        }
    }

    /// Speech auth, requested only now (whisper path never needs it). Denied or
    /// restricted → empty (we will not fall back to the server).
    private func ensureAuth(_ completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { completion(status == .authorized) }
            }
        default: completion(false)
        }
    }
}

// MARK: - anti-hallucination filter

/// whisper invents phantom text on near-silent audio ("you", "Thank you.",
/// "[BLANK_AUDIO]", looped lines). The RMS gate stops most of it upstream; this
/// is the mandatory second guard on the text itself.
enum Hallucination {
    private static let phantoms: Set<String> = [
        "you", "thank you", "thank you.", "thanks for watching", "thanks for watching.",
        "thanks for watching!", "[blank_audio]", "[music]", "(music)", "[applause]", "(applause)",
        "[laughter]", "(laughter)", "(pause)", "(silence)", "[silence]", "bye", "bye.", "bye!",
        ".", "...", "♪", "♪♪",
    ]

    static func filter(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // Collapse a looped run of one identical line (a whisper failure mode).
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if lines.count >= 2, Set(lines).count == 1 { return "" }
        if !lines.isEmpty { s = collapseConsecutiveDuplicates(lines).joined(separator: "\n") }

        let lower = s.lowercased()
        if phantoms.contains(lower) { return "" }
        // A lone bracketed/parenthesized tag with no real words (e.g. "[music]", "(silence)").
        if (s.hasPrefix("[") && s.hasSuffix("]")) || (s.hasPrefix("(") && s.hasSuffix(")")),
           !s.dropFirst().dropLast().contains(" ") || lower.contains("blank") || lower.contains("silence") || lower.contains("music") {
            return ""
        }
        return s
    }

    private static func collapseConsecutiveDuplicates(_ lines: [String]) -> [String] {
        var out: [String] = []
        for l in lines where out.last != l { out.append(l) }
        return out
    }
}

#if DEBUG
// MARK: - bench stub engine (DEBUG builds only)

/// The regression smoke's engine (WARBLE_FORCE_ENGINE=stub): opens the WAV like a real engine —
/// so a broken fixture fails the run — then returns a fixed messy utterance, making the whole
/// paste-path pipeline (spell → clean → dictionary) assertable exactly on any machine with no
/// model installed and no Speech authorization.
final class StubTranscriber: Transcriber {
    static let utterance = "um so the the quick brown fox"

    func transcribe(_ wav: URL, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let readable = (try? AVAudioFile(forReading: wav)) != nil
            DispatchQueue.main.async { completion(readable ? Self.utterance : nil) }
        }
    }
}
#endif
