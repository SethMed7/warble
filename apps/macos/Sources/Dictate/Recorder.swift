import AVFoundation
import Shared

/// Records raw mic audio for the whole hotkey hold into an in-flight WAV — no
/// recognizer, no endpointer, no silence cutoff. The finger is the only
/// endpoint: while the key is held we just keep writing, through any number of
/// thinking pauses. Transcription happens once, after release (see Transcriber).
///
/// The in-flight WAV is warble's crash buffer (product.md §4.10): written
/// incrementally under ~/.warble/inflight — regardless of the Save-recordings
/// setting — so a crash/force-quit mid-dictation leaves the words recoverable
/// (see Recovery). Every clean end of a session promotes or deletes it.
///
/// Replaces the old streaming SFSpeechRecognizer, whose silence-finalize was the
/// "stop talking then start again and it forgets things" bug.
final class Recorder {
    struct Result {
        let url: URL            // temp 32-bit float WAV (whisper-cli reads it directly)
        let duration: TimeInterval
        let peak: Float         // loudest sample magnitude — the silence/short-tap gate
        let capped: Bool        // hit the runaway safety ceiling (stuck key)
    }

    /// Runaway protection only — NOT an endpointer. A missed key-up (a known
    /// Carbon hot-key failure mode) shouldn't grow a file forever. We stop
    /// writing past this; the user still gets the first MAX_SECONDS.
    private static let maxSeconds: Double = 5 * 60

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var url: URL?
    private var configObserver: Any? // watches for the input device vanishing mid-recording
    private var active = false
    private var frames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var peak: Float = 0
    private var capped = false

    /// Live normalized mic level (0…1) for the dictation waveform, emitted on the
    /// main thread per audio buffer (~12×/s). Set before `start`; nil = no meter.
    var onLevel: ((Float) -> Void)?

    /// Fired (main thread) when the input device vanishes mid-recording — unplugged, or a
    /// Bluetooth mic dropping. The session owner ends the dictation naming the cause; the audio
    /// captured up to the drop is still in the file and is delivered, not lost.
    var onDisconnect: (() -> Void)?

    /// Start recording to a fresh temp WAV. Mic permission is requested here
    /// (whisper needs no Speech entitlement). onError fires if we can't record.
    func start(onError: @escaping (DictateError) -> Void) {
        active = true
        frames = 0
        peak = 0
        capped = false
        if Fault.isActive(.micBusy) { active = false; onError(.micBusy); return }
        requestMic { [weak self] granted in
            guard let self, self.active else { return } // released during the dialog
            guard granted else { self.active = false; onError(.micPermission); return }
            self.begin(onError: onError)
        }
    }

    private func begin(onError: @escaping (DictateError) -> Void) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { active = false; onError(.noMic); return }
        sampleRate = format.sampleRate
        let maxFrames = AVAudioFramePosition(Self.maxSeconds * sampleRate)

        let tmp = Recovery.newInflightURL()
        do {
            file = try AVAudioFile(forWriting: tmp, settings: format.settings)
        } catch {
            active = false
            Log.dictate.error("in-flight WAV create failed: \(error.localizedDescription, privacy: .public)")
            onError(.recordFailed)
            return
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        url = tmp

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, self.active else { return }
            if self.frames >= maxFrames { self.capped = true; return } // runaway guard
            self.trackPeak(buffer)
            try? self.file?.write(from: buffer)
            self.frames += AVAudioFramePosition(buffer.frameLength)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            active = false
            file = nil
            // A device is present but capture couldn't start — in practice another app holding
            // the input exclusively. The underlying error is logged for the exotic cases.
            Log.dictate.error("engine.start failed: \(error.localizedDescription, privacy: .public)")
            onError(.micBusy)
            return
        }
        self.engine = engine
        // The input device can vanish mid-hold: the engine stops silently and no more buffers
        // arrive. Detect it so the session ends naming the cause instead of pasting a mystery.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.active else { return }
            if engine.inputNode.outputFormat(forBus: 0).sampleRate == 0 || !engine.isRunning {
                Log.dictate.error("input device vanished mid-recording (configuration change)")
                self.onDisconnect?()
            }
        }
        if Fault.isActive(.micDisconnected) { // debug-only: simulate the drop shortly after start
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.active else { return }
                self.onDisconnect?()
            }
        }
    }

    /// Stop and hand back the recorded clip (or nil if nothing was captured).
    /// removeTap first so no further writes race the close.
    func stop() -> Result? {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        guard active else { return nil }
        active = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        file = nil // ARC closes/flushes the WAV
        guard let url, sampleRate > 0, frames > 0 else {
            if let url { try? FileManager.default.removeItem(at: url) } // header-only WAV, no audio captured — don't orphan it
            return nil
        }
        let duration = Double(frames) / sampleRate
        return Result(url: url, duration: duration, peak: peak, capped: capped)
    }

    /// Loudest sample magnitude in this buffer — drives the silence gate so a
    /// key-tap with no speech never reaches whisper (which hallucinates on
    /// silence). Falls back to "assume signal" for non-float formats.
    private func trackPeak(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { peak = max(peak, 1); return }
        let n = Int(buffer.frameLength)
        let samples = ch[0]
        var localMax: Float = 0
        var sumSq: Float = 0
        for i in 0..<n {
            let s = samples[i]
            let a = abs(s)
            if a > localMax { localMax = a }
            sumSq += s * s
        }
        if localMax > peak { peak = localMax }
        // Drive the live waveform from RMS. Speech RMS is small (~0.02–0.1), so a linear map barely
        // moves the bars — use a perceptual sqrt curve with real gain (after a tiny noise floor) so
        // the bars clearly track your voice and rest flat in silence.
        if let onLevel, n > 0 {
            let rms = (sumSq / Float(n)).squareRoot()
            // Low noise floor + strong gain on the perceptual sqrt curve, so even quiet/normal speech
            // drives the bars well up (loud speech saturates — that's the intended big reaction).
            let level = min(1, max(0, rms - 0.0025).squareRoot() * 4.8)
            DispatchQueue.main.async { onLevel(level) }
        }
    }

    private func requestMic(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }
}
