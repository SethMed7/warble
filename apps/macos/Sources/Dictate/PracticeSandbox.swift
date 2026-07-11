import Foundation

/// The onboarding practice card's seam into the dictation pipeline (ROADMAP 0.4 "guaranteed
/// first success"). While a rehearsal is active AND warble itself is frontmost when recording
/// starts, DictateController tags the session `sandbox: true`: the dictation runs the REAL
/// gesture → record → transcribe → clean path, but the result is handed here — the card shows
/// the raw → cleaned transformation — instead of being pasted, remembered, recorded into
/// History/stats, or watched for corrections. A rehearsal must leave no trace, and must never
/// type into whatever app focus wandered off to mid-hold. Main thread only.
public final class PracticeSandbox {
    public static let shared = PracticeSandbox()
    public private(set) var isActive = false
    private var onResult: ((_ raw: String, _ cleaned: String) -> Void)?

    /// The practice card is visible — dictations that start on warble become rehearsals.
    public func begin(onResult: @escaping (_ raw: String, _ cleaned: String) -> Void) {
        isActive = true
        self.onResult = onResult
    }

    /// The card is gone — dictation is real again.
    public func end() {
        isActive = false
        onResult = nil
    }

    /// DictateController hands a sandboxed dictation's transformation to the card. Returns false
    /// when the card already closed mid-flight — the result is simply dropped (it was a rehearsal).
    @discardableResult
    func deliver(raw: String, cleaned: String) -> Bool {
        guard let onResult else { return false }
        onResult(raw, cleaned)
        return true
    }
}
