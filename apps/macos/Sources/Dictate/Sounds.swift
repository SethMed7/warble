import AVFoundation

/// The audible half of the listening contract (ROADMAP 0.4): a soft ping the moment the mic goes
/// hot, and a distinct, quieter one on a clean stop — so "did it hear me?" never needs eyes.
/// Cancel and error paths stay silent (0.3's error states already speak for those).
///
/// The pings are synthesized in-process (two short decaying sines — no bundled asset, no
/// networking, a few KB of PCM each). Toggle: menu → Dictate → Sounds, persisted in UserDefaults;
/// off means off until the user says otherwise (product.md §4.5 — nothing re-enables itself).
enum DictateSounds {
    /// Whether the start/stop pings play. On by default — the ping IS the contract — but one
    /// click away and persistent. Read fresh each play, so a toggle applies immediately.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "dictateSounds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dictateSounds") }
    }

    /// Mic just went hot (engine started, buffers flowing) — the "it's listening" ping.
    static func playStart() { play(&startPlayer, data: startData) }

    /// A clean, user-intended stop (release / hands-free stop / the cap's clean stop) — lower
    /// and quieter than the start, so the pair reads as open/close without demanding attention.
    static func playStop() { play(&stopPlayer, data: stopData) }

    // MARK: synthesis — pure functions, unit-tested (DictateTests/SoundsTests)

    static let sampleRate = 24_000.0 // plenty for sub-1kHz pings; keeps the buffers tiny

    /// One soft ping: a sine with a short linear attack and an exponential decay, ending in a
    /// brief fade to exactly zero so playback can never click. Amplitude is the ceiling; the
    /// decay spends most of the ping well under it — subtle by construction.
    static func tone(frequency: Double, seconds: Double, amplitude: Double) -> [Float] {
        let n = Int(seconds * sampleRate)
        let attack = min(n, Int(0.006 * sampleRate))     // 6ms in — no thump
        let fade = min(n, Int(0.010 * sampleRate))       // 10ms out — no click
        let tau = seconds / 4.5                          // decay reaches ~1% by the end
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            var env = exp(-t / tau)
            if i < attack { env *= Double(i) / Double(attack) }
            if i >= n - fade { env *= Double(n - i) / Double(fade) }
            return Float(amplitude * env * sin(2 * .pi * frequency * t))
        }
    }

    /// Wrap samples as a minimal in-memory WAV (16-bit mono PCM) — what AVAudioPlayer plays.
    static func wav(_ samples: [Float]) -> Data {
        let rate = UInt32(sampleRate)
        let dataBytes = UInt32(samples.count * 2)
        var d = Data(capacity: 44 + samples.count * 2)
        func put(_ s: String) { d.append(contentsOf: s.utf8) }
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        put("RIFF"); put32(36 + dataBytes); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1); put32(rate); put32(rate * 2); put16(2); put16(16)
        put("data"); put32(dataBytes)
        for s in samples {
            let clamped = max(-1, min(1, s))
            put16(UInt16(bitPattern: Int16(clamped * Float(Int16.max))))
        }
        return d
    }

    // MARK: playback plumbing

    // A5 in, D5 out — a fifth apart, unmistakably two different events; the stop is quieter.
    private static let startData = wav(tone(frequency: 880, seconds: 0.12, amplitude: 0.30))
    private static let stopData = wav(tone(frequency: 587.33, seconds: 0.10, amplitude: 0.18))
    private static var startPlayer: AVAudioPlayer?
    private static var stopPlayer: AVAudioPlayer?

    private static func play(_ player: inout AVAudioPlayer?, data: Data) {
        guard enabled else { return }
        if player == nil { player = try? AVAudioPlayer(data: data) }
        guard let p = player else { return }
        p.currentTime = 0
        p.play()
    }
}
