import AVFoundation
import SwiftUI
import Shared

/// The welcome tour's live input-level meter (ROADMAP 0.4 "guaranteed first success"): proof
/// that warble hears you BEFORE any dictation is asked for. An AVAudioEngine tap reduces each
/// buffer to one RMS level and drops it — no file, no transcription, nothing leaves the process.
/// It runs ONLY while the meter card is visible (motion is the signal — DESIGN.md), and only
/// when the mic is already granted: `start()` never prompts (the card's jump-back handles the
/// not-granted state). Main thread only.
final class MicMeter: ObservableObject {
    /// Displayed bar heights (0…1), eased toward the live level per frame — the dictation pill's
    /// fast-attack/slow-release VU feel (MicWaveformView), re-expressed as published SwiftUI
    /// state so the card stays a pure view the render seam can rasterize.
    @Published private(set) var levels = MicMeter.resting
    static let bars = 17 // wider card than the pill → more bars, same slim capsules
    static let resting = [CGFloat](repeating: 0.06, count: bars)

    private var engine: AVAudioEngine?
    private var timer: Timer?
    private var target: CGFloat = 0
    private var phase: CGFloat = 0

    func start() {
        guard engine == nil,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return } // no input device — the bars just rest
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let ch = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sumSq: Float = 0
            for i in 0..<n { let s = ch[0][i]; sumSq += s * s }
            // The same perceptual curve as the pill's recorder: tiny noise floor, sqrt, real
            // gain — quiet speech still clearly moves the bars (Recorder.trackPeak).
            let level = min(1, max(0, (sumSq / Float(n)).squareRoot() - 0.0025).squareRoot() * 4.8)
            DispatchQueue.main.async { self.target = CGFloat(level) }
        }
        engine.prepare()
        guard (try? engine.start()) != nil else {
            input.removeTap(onBus: 0)
            return // mic busy elsewhere — the card stays calm; dictation will name such causes
        }
        self.engine = engine
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common) // keep easing while the user drags the window
        timer = t
    }

    /// Card gone (next step, jump back, window closed) — the tap and the motion stop together.
    func stop() {
        timer?.invalidate(); timer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        target = 0
        phase = 0
        levels = Self.resting
    }

    private func tick() {
        phase += 0.84 // 30fps — same traveling-sine speed as the pill's 60fps 0.42 step
        var next = levels
        for i in next.indices {
            // The pill's ripple shaping: a traveling sine so the row undulates instead of moving
            // as one block, snappy attack and slower release per bar.
            let ripple = 0.5 + 0.5 * sin(phase + CGFloat(i) * 1.15)
            let goal = max(0.05, target * (0.40 + 0.60 * ripple))
            let k: CGFloat = goal > next[i] ? 0.6 : 0.16
            next[i] += (goal - next[i]) * k
        }
        levels = next
    }

    deinit {
        timer?.invalidate()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
    }
}

/// The meter's bars — the dictation pill's waveform idiom (rounded electric bars + the
/// lit-signal glow) in pure SwiftUI, because ImageRenderer skips AppKit-backed views like the
/// pill's MicWaveformView. The live card and the `--render-onboarding` seam draw THIS view
/// (live levels vs an injected fixture), so headless and on-screen can't drift.
struct MeterBars: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let n = max(1, levels.count)
            let gap: CGFloat = 5
            // Slim capsules like the pill's — never blobs: width is capped, the row centers.
            let barW = min(7, max(2.5, (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n)))
            HStack(spacing: gap) {
                ForEach(levels.indices, id: \.self) { i in
                    Capsule()
                        .fill(Theme.electric.color)
                        .frame(width: barW, height: max(4, min(1, levels[i]) * geo.size.height))
                        // The Lit-Signal Rule: the waveform bars are the app's entire glow budget.
                        .shadow(color: Theme.electric.color.opacity(0.7), radius: 4)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
