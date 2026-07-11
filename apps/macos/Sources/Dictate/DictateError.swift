import Foundation

/// The dictate-flow error taxonomy (ROADMAP 0.3 "cause-naming errors"): every failure branch names
/// its cause in user-facing copy — never a generic toast — shown in the pill and the menu, and
/// logged with a stable `reason` slug (see Shared/Log). `--errors` prints the whole table and
/// regression.sh asserts it verbatim, so any copy change is a deliberate one.
enum DictateError: CaseIterable {
    case micPermission        // Microphone permission denied or restricted
    case micBusy              // an input device exists but capture couldn't start — in use elsewhere
    case micDisconnected      // the input device vanished mid-dictation (unplugged, Bluetooth drop)
    case noMic                // no input device at all
    case recordFailed         // couldn't create/write the temp WAV
    case engineWarming        // processing stalled while the warm engine was still loading its model
    case processingTimeout    // processing stalled for any other reason
    case transcribeFailed     // every engine errored and the recording could NOT be kept (saving off / secure field)
    case transcribeFailedKept // every engine errored; the recording is kept under ~/.warble/audio
    case engineMissing        // a notice, not a failure (plain pill, no warn): dictation ran on the Apple floor

    /// Stable log/test slug — never shown to the user.
    var reason: String {
        switch self {
        case .micPermission: return "mic-permission"
        case .micBusy: return "mic-busy"
        case .micDisconnected: return "mic-disconnected"
        case .noMic: return "no-mic"
        case .recordFailed: return "record-failed"
        case .engineWarming: return "engine-warming"
        case .processingTimeout: return "processing-timeout"
        case .transcribeFailed: return "transcribe-failed"
        case .transcribeFailedKept: return "transcribe-failed-kept"
        case .engineMissing: return "engine-missing"
        }
    }

    /// User-facing copy — calm, plain, names the cause (product.md tone).
    var message: String {
        switch self {
        case .micPermission: return "grant Microphone access in System Settings"
        case .micBusy: return "mic is in use by another app"
        case .micDisconnected: return "mic disconnected mid-dictation"
        case .noMic: return "no microphone found"
        case .recordFailed: return "couldn't start recording"
        case .engineWarming: return "engine still warming up — try again in a moment"
        case .processingTimeout: return "took too long — press Fn to retry"
        case .transcribeFailed: return "transcription failed"
        case .transcribeFailedKept: return "transcription failed — recording kept"
        case .engineMissing: return "premium engine not installed — using Apple engine"
        }
    }
}

/// Debug-only fault injection: WARBLE_FAULT=mic-busy|mic-disconnected|engine-warming|engine-missing|
/// transcribe-fail forces one failure path so its cause-naming copy can be exercised — headlessly by
/// regression.sh (engine-missing, transcribe-fail via the CLI) and by hand in the app (the mic
/// faults). Compiled out of release builds, so it can never alter shipped behavior.
enum Fault: String {
    case micBusy = "mic-busy"
    case micDisconnected = "mic-disconnected"
    case engineWarming = "engine-warming"
    case engineMissing = "engine-missing"
    case transcribeFail = "transcribe-fail"

    static func isActive(_ f: Fault) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["WARBLE_FAULT"] == f.rawValue
        #else
        return false
        #endif
    }
}
