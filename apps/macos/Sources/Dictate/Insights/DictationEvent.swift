import Foundation

/// One recorded dictation, persisted as a single JSON line in ~/.warble/history.json: the cleaned
/// text (empty in stats-only mode) plus the metrics that power the dashboard (the audio, when
/// saved, lives separately under ~/.warble/audio). `day` is precomputed in the user's LOCAL
/// timezone so streak math is a plain calendar walk that can't drift at midnight/DST.
struct DictationEvent: Codable, Identifiable, Hashable {
    let id: String
    let ts: Double            // Unix epoch seconds, UTC — the source of truth for time
    let day: String           // "yyyy-MM-dd" in the user's local timezone — the streak / per-day key
    let text: String          // the full cleaned transcript ("" when History is off)
    let raw: String?          // the verbatim transcript, kept only when cleanup changed it — so any
                              // polish is undoable ("what I actually said"); text only, no extra audio.
                              // Optional so pre-0.3 history lines still decode.
    let words: Int
    let durationMs: Int
    let appBundleId: String?
    let appName: String?
    let engine: String
    let kind: String          // "dictate" now; "read" reserved so read-aloud can share the log later
    let status: String?       // nil = delivered; "failed" = transcription failed and the recording
                              // is kept for recovery (replay + Re-transcribe in History).
                              // Optional so pre-recovery history lines still decode.
    let context: ContextRecord?  // what context awareness read for this dictation (ROADMAP 0.6):
                              // app, category, word count, ≤12-word preview — never the full
                              // text (structurally: ContextRecord's only initializer caps it).
                              // Optional so pre-0.6 history lines still decode; nil when the
                              // toggle is off (the default) or the capture was gated.
    let correctionsCleaned: Int?  // filler/false-start/duplicate removals the deterministic
                              // cleanup layer made over the raw ASR text (ROADMAP 0.6 dashboard —
                              // "corrections cleaned for you"), counted at clean time
                              // (BasicCleaner.correctionsCount) since it can't be recovered later
                              // from the already-cleaned, stored transcript. A pure count, never
                              // gated by the History/secure-field toggles the way text is — same
                              // "metric, not content" bucket as words/durationMs. Optional so
                              // pre-0.6.1 history lines still decode, and nil for events nothing
                              // was measured for (a FAILED transcription, a read-aloud).

    var isFailed: Bool { status == "failed" }
    var date: Date { Date(timeIntervalSince1970: ts) }
    var wpm: Int { durationMs > 0 ? Int((Double(words) / (Double(durationMs) / 60_000.0)).rounded()) : 0 }
}

/// The bits captured at dictation time that `deliver` doesn't otherwise have — threaded from
/// `transcribeAndDeliver` (which holds the clip) and from the frontmost app at recording start.
struct DictationContext {
    let durationMs: Int
    let engine: String
    let appBundleId: String?
    let appName: String?
    let secure: Bool   // a secure (password) field was focused while recording — keep metrics only
    var sandbox = false // an onboarding rehearsal (PracticeSandbox) — History/stats must not move
    var context: CapturedContext? = nil // context awareness's in-memory capture (ROADMAP 0.6) —
                                        // nil when off (the default), secure, or sandbox; only its
                                        // bounded ContextRecord derivative ever reaches disk
    var correctionsCleaned = 0  // set once cleanup has actually run (ROADMAP 0.6 dashboard) — 0
                                // for level None (verbatim) or before the count is computed;
                                // InsightStore.record copies it onto the stored DictationEvent
}
