import AppKit
import Carbon.HIToolbox

/// Extra dictation triggers beyond the built-in Fn (ROADMAP 0.5 "multi-shortcut + mouse
/// bindings"): up to three bindings, each { trigger, gesture }, so the RSI/accessibility audience
/// can put push-to-talk on a thumb button. A binding is an ALIAS of Fn, never a mode — identical
/// hold / double-tap semantics (HotKey.swift), same pill, same Esc — and Fn itself stays: built
/// in, always active while Dictate is on, not removable.
///
/// Persisted in UserDefaults ("dictateBindings", a string array like ["right-command:hold"]) so
/// the regression suite can seed one with a plain `defaults write` — the same cross-process seam
/// as the cleanup level and the sounds toggle. The parse/validate/decode halves are pure static
/// funcs (unit-tested with no defaults, no events); a hand-planted invalid array is dropped
/// entry-by-entry on load and can never wedge the tap.

/// What the user presses. The vocabulary IS the safety rail: only keys and buttons that macOS
/// leaves free can even be expressed — Esc (the cancel key), ⌃V (read-aloud), letters, and the
/// system's own F1–F12 are structurally out; the picker offers exactly this list.
enum BindingTrigger: Equatable, Hashable {
    case rightCommand
    case rightOption
    case fkey(Int)   // F13…F19 — the lower F-keys belong to macOS
    case mouse(Int)  // button 3…10 (1 and 2 are the Mac's own clicks); thumb buttons are usually 4/5

    static let allCases: [BindingTrigger] =
        [.rightCommand, .rightOption]
        + (13...19).map { .fkey($0) }
        + (3...10).map { .mouse($0) }

    /// The persisted/CLI token ("right-command", "f13", "mouse-4").
    var spec: String {
        switch self {
        case .rightCommand: return "right-command"
        case .rightOption: return "right-option"
        case .fkey(let n): return "f\(n)"
        case .mouse(let n): return "mouse-\(n)"
        }
    }

    /// The human name the dashboard shows.
    var display: String {
        switch self {
        case .rightCommand: return "right ⌘"
        case .rightOption: return "right ⌥"
        case .fkey(let n): return "F\(n)"
        case .mouse(let n): return n == 3 ? "mouse button 3 (middle)" : "mouse button \(n)"
        }
    }

    // MARK: event matching — the pure facts HotKey routes real events with (unit-tested)

    /// The modifier-key triggers — the ones a keyboard chord (right-⌘ C…) must taint, exactly
    /// like Fn + a key never dictates.
    var isModifier: Bool { self == .rightCommand || self == .rightOption }

    /// The coarse NSEvent flag a modifier trigger sets — masked OUT of its own taint set
    /// (a trigger can't taint itself).
    var modifierFlag: NSEvent.ModifierFlags? {
        switch self {
        case .rightCommand: return .command
        case .rightOption: return .option
        default: return nil
        }
    }

    /// The device-dependent bit in `NSEvent.modifierFlags.rawValue` that tells the RIGHT-side key
    /// from the left (NX_DEVICERCMDKEYMASK / NX_DEVICERALTKEYMASK) — the coarse .command/.option
    /// flag alone can't, and a left-⌘ shortcut must never start a dictation.
    var deviceBit: UInt? {
        switch self {
        case .rightCommand: return 0x0010
        case .rightOption: return 0x0040
        default: return nil
        }
    }

    /// The F-key's hardware key code (non-contiguous — Carbon's kVK table is the canon).
    var fkeyKeyCode: UInt16? {
        switch self {
        case .fkey(13): return UInt16(kVK_F13)
        case .fkey(14): return UInt16(kVK_F14)
        case .fkey(15): return UInt16(kVK_F15)
        case .fkey(16): return UInt16(kVK_F16)
        case .fkey(17): return UInt16(kVK_F17)
        case .fkey(18): return UInt16(kVK_F18)
        case .fkey(19): return UInt16(kVK_F19)
        default: return nil
        }
    }

    /// `NSEvent.buttonNumber` for the mouse triggers — user-facing button N is event number N−1
    /// (button 3 is the middle button, 2 in event terms).
    var mouseButtonNumber: Int? {
        if case .mouse(let n) = self { return n - 1 }
        return nil
    }
}

/// How the trigger is used — the same two gestures Fn speaks.
enum BindingGesture: String, CaseIterable {
    case hold = "hold"            // push-to-talk: record while held
    case doubleTap = "double-tap" // hands-free toggle: start, then stop

    var display: String { self == .hold ? "hold to talk" : "double-tap to toggle" }
}

/// One binding. The same trigger MAY carry both gestures (two bindings) — that's exactly how Fn
/// itself works; the timing disambiguation is shared (HotKey).
struct DictationBinding: Equatable, Hashable {
    let trigger: BindingTrigger
    let gesture: BindingGesture
    var spec: String { "\(trigger.spec):\(gesture.rawValue)" }
}

/// The store + the pure validation. Every rejection carries the plain reason the dashboard (and
/// `--bindings add`) shows.
final class Bindings {
    static let shared = Bindings()
    static let maxExtra = 3 // besides Fn
    static let defaultsKey = "dictateBindings"

    private(set) var list: [DictationBinding] = []

    init() { load() }

    func load() {
        list = Self.decode(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    private func save() {
        UserDefaults.standard.set(list.map(\.spec), forKey: Self.defaultsKey)
    }

    enum Outcome: Equatable { case added(DictationBinding), rejected(String) }

    /// The dashboard's Add (and `--bindings add`) — one validation path, one reason vocabulary.
    func add(_ spec: String) -> Outcome {
        switch Self.parse(spec) {
        case .bad(let reason): return .rejected(reason)
        case .ok(let b): return add(b)
        }
    }

    func add(_ b: DictationBinding) -> Outcome {
        if let reason = Self.rejectionReason(adding: b, to: list) { return .rejected(reason) }
        list.append(b)
        save()
        return .added(b)
    }

    /// The dashboard's delete (and `--bindings remove`).
    @discardableResult
    func remove(_ b: DictationBinding) -> Bool {
        guard list.contains(b) else { return false }
        list.removeAll { $0 == b }
        save()
        return true
    }

    // MARK: pure halves — no defaults, no events

    enum ParseResult: Equatable { case ok(DictationBinding), bad(String) }

    /// "trigger:gesture" → a binding, or the plain reason it can't be one.
    static func parse(_ spec: String) -> ParseResult {
        let parts = spec.lowercased().split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return .bad("use trigger:gesture — e.g. right-command:hold")
        }
        switch parseTrigger(String(parts[0])) {
        case .bad(let reason): return .bad(reason)
        case .ok(let trigger):
            guard let gesture = BindingGesture(rawValue: String(parts[1])) else {
                return .bad("unknown gesture \"\(parts[1])\" — use hold or double-tap")
            }
            return .ok(DictationBinding(trigger: trigger, gesture: gesture))
        }
    }

    enum TriggerParse: Equatable { case ok(BindingTrigger), bad(String) }

    /// The reserved/OS-owned rejections live here, each with its plain reason.
    static func parseTrigger(_ s: String) -> TriggerParse {
        switch s {
        case "right-command": return .ok(.rightCommand)
        case "right-option": return .ok(.rightOption)
        case "fn", "globe":
            return .bad("Fn is built in — always a dictation trigger while Dictate is on, and can't be re-bound")
        case "esc", "escape":
            return .bad("Esc cancels a dictation — it can't also start one")
        default:
            if s.hasPrefix("f"), let n = Int(s.dropFirst()) {
                return (13...19).contains(n) ? .ok(.fkey(n))
                    : .bad("only F13–F19 can be bound — the lower F-keys belong to macOS")
            }
            if s.hasPrefix("mouse-"), let n = Int(s.dropFirst(6)) {
                if (3...10).contains(n) { return .ok(.mouse(n)) }
                return .bad("mouse buttons 1 and 2 are your Mac's own clicks — pick button 3–10")
            }
            return .bad("unknown trigger \"\(s)\" — use right-command, right-option, f13–f19, or mouse-3…mouse-10")
        }
    }

    /// nil = the add is fine. The same trigger with the OTHER gesture is deliberately allowed —
    /// that's Fn's own shape (one key, both gestures, timing disambiguates).
    static func rejectionReason(adding b: DictationBinding, to list: [DictationBinding]) -> String? {
        if list.contains(b) { return "\(b.trigger.display) (\(b.gesture.display)) is already bound" }
        if list.count >= maxExtra { return "up to \(maxExtra) bindings besides Fn — remove one first" }
        return nil
    }

    /// Load-time hygiene for the defaults seam: drop anything unparseable, dedupe exact repeats,
    /// cap at maxExtra — a hand-planted array degrades gracefully to the valid prefix.
    static func decode(_ specs: [String]) -> [DictationBinding] {
        var out: [DictationBinding] = []
        for s in specs {
            guard case .ok(let b) = parse(s), !out.contains(b), out.count < maxExtra else { continue }
            out.append(b)
        }
        return out
    }
}
