import Foundation

/// The read-aloud error taxonomy (ROADMAP 0.3 "cause-naming errors"): named causes for the
/// follow-along panel's status line — never a raw stderr dump — each with a stable log slug
/// (see Shared/Log). Printed by `--errors` and asserted verbatim in regression.sh.
enum SpeakError: CaseIterable {
    case renderFailed // the Kokoro renderer produced no audio (warm and cold paths both failed)
    case readCutOff   // the renderer died mid-stream — the tail of the selection is lost
    case voiceMissing // a notice, not a failure: a premium voice is picked but Kokoro isn't installed
    case noSelection  // "Read Selection" found nothing to read

    /// Stable log/test slug — never shown to the user.
    var reason: String {
        switch self {
        case .renderFailed: return "render-failed"
        case .readCutOff: return "read-cut-off"
        case .voiceMissing: return "voice-missing"
        case .noSelection: return "no-selection"
        }
    }

    /// User-facing copy — calm, plain, names the cause (product.md tone).
    var message: String {
        switch self {
        case .renderFailed: return "voice engine failed"
        case .readCutOff: return "read cut off"
        case .voiceMissing: return "premium voice not installed — using Apple voice"
        case .noSelection: return "no text selected"
        }
    }
}
