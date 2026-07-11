import Foundation

/// The long-session cap (ROADMAP 0.3 — long-session hardening). One number owns the whole story:
/// the controller stops the session CLEANLY at the cap (everything captured is transcribed and
/// lands normally, the cause is named — never a silent truncation), the pill counts down the last
/// warnWindow, and the Recorder's runaway ceiling sits a margin above so no audio is dropped
/// before the clean stop.
///
/// 20 minutes matches the researched category norm (Wispr Flow caps at 20 with a warning at 19)
/// and fits inside Parakeet TDT's ~24-minute single-pass window, so even a maxed-out clip is one
/// pass for the premium engine.
enum HoldCap {
    /// WARBLE_MAX_HOLD_SECS (debug builds only) compresses the cap so the warn→cap machine can be
    /// exercised in seconds — regression.sh drives it via --hold-cap / --hold-cap-sim.
    static var maxSeconds: Double {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["WARBLE_MAX_HOLD_SECS"],
           let v = Double(raw), v > 0 { return v }
        #endif
        return 20 * 60
    }

    /// The countdown starts this long before the cap — halved for tiny debug caps so the warning
    /// still *precedes* the stop instead of swallowing the whole session.
    static func warnWindow(for cap: Double) -> Double { min(60, cap / 2) }

    /// "20-minute" (or "6-second" under a debug override) — the human form for the stop copy.
    static var label: String {
        let s = maxSeconds
        if s >= 120, s.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(s / 60))-minute" }
        return "\(Int(s))-second"
    }
}

/// The per-session warn→cap state machine, UI-free so the CLI can prove it headlessly
/// (--hold-cap-sim): one timer that starts ticking at cap−warnWindow (once per second, main run
/// loop, .common so menu tracking can't freeze the countdown), reporting whole seconds remaining,
/// then fires onCap once the deadline passes. Remaining time is computed from the deadline, not
/// counted, so timer jitter can't drift the cap. cancel() is idempotent; a clean key-release
/// simply cancels the clock.
final class HoldCapClock {
    private let deadline: Date
    private let onTick: (Int) -> Void
    private let onCap: () -> Void
    private var timer: Timer?

    init(cap: Double = HoldCap.maxSeconds, onTick: @escaping (Int) -> Void, onCap: @escaping () -> Void) {
        deadline = Date(timeIntervalSinceNow: cap)
        self.onTick = onTick
        self.onCap = onCap
        let warnStart = max(Date(), deadline.addingTimeInterval(-HoldCap.warnWindow(for: cap)))
        let t = Timer(fire: warnStart, interval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func cancel() { timer?.invalidate(); timer = nil }

    private func tick() {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0.05 {
            cancel()
            onCap()
        } else {
            onTick(Int(remaining.rounded()))
        }
    }

    deinit { timer?.invalidate() }
}
