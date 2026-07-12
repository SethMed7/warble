import AppKit
import Carbon.HIToolbox

/// Dictate → read-back proofread (ROADMAP 0.5): right after a dictation lands, ⌃R reads it back
/// through the normal read-aloud pipeline — the bidirectional loop as one gesture. Two halves:
///
///   • `ReadBackAvailability` — the pure availability machine (no timers, no Carbon, no UI):
///     landed → available → expired/consumed, with the per-mode gate (read-aloud off → never
///     available). Unit-tested in ReadBackTests; `--readback-state` prints its story for
///     regression.sh.
///   • `ReadBackKey` — the transient Carbon ⌃R claim. Never a standing hotkey (product.md §4.6):
///     registered the moment a dictation lands, released on use, expiry, supersession, or a mode
///     turning off — so ⌃R stays a normal key (terminal reverse-search, apps' own shortcuts)
///     except for the brief window when warble has something to read back.
///
/// DictateController owns the live wiring; the app coordinator routes the fired text into the
/// Speak module's one-shot read (follow-along panel, word-by-word, Esc stops).
struct ReadBackAvailability {
    /// The grace window. 15 seconds: the landed pill itself is gone in under 2s, so the window is
    /// what makes ⌃R reachable after it — long enough to re-read the sentence you just landed and
    /// decide you want to hear it, short enough that the global ⌃R claim can never surprise you
    /// minutes later in a terminal. Past expiry the menu item (Dictate ▸ Read Last Dictation
    /// Back) still reads the last dictation any time; only the hotkey is transient.
    static let graceSeconds: TimeInterval = 15

    enum Phase: String { case idle, available, expired, consumed }

    private var text: String?
    private var armedAt: TimeInterval = 0
    private var used = false

    /// A dictation landed. Returns true when read-back armed (the ⌃R claim should register) —
    /// false when read-aloud is off (per-mode law, product.md §4.5: an off mode registers
    /// nothing) or there's nothing to read.
    mutating func landed(_ t: String, at now: TimeInterval, speakEnabled: Bool) -> Bool {
        guard speakEnabled, !t.isEmpty else { cancel(); return false }
        text = t
        armedAt = now
        used = false
        return true
    }

    /// ⌃R: the just-landed text while still available, else nil (expired / already consumed /
    /// nothing landed). One-shot — a successful consume ends the availability.
    mutating func consume(at now: TimeInterval) -> String? {
        guard phase(at: now) == .available, let t = text else { return nil }
        used = true
        return t
    }

    func phase(at now: TimeInterval) -> Phase {
        guard text != nil else { return .idle }
        if used { return .consumed }
        return now - armedAt < Self.graceSeconds ? .available : .expired
    }

    /// Availability withdrawn: a new dictation started, or a mode turned off.
    mutating func cancel() {
        text = nil
        used = false
    }

    /// `--readback-state` — the availability story, told by the REAL machine against a synthetic
    /// clock and asserted verbatim by regression.sh (check: readback). The live wiring — the
    /// transient claim, the Speak handoff — is by-hand: docs/testing.md.
    static func printStory() {
        var m = ReadBackAvailability()
        var now: TimeInterval = 0
        print("grace \(Int(graceSeconds))s")
        _ = m.landed("the words", at: now, speakEnabled: true)
        print("landed (speak on) -> \(m.phase(at: now).rawValue) · ⌃R armed")
        now += graceSeconds
        print("+\(Int(graceSeconds))s -> \(m.phase(at: now).rawValue) · ⌃R released")
        _ = m.landed("the words", at: now, speakEnabled: true)
        print("landed again -> \(m.phase(at: now).rawValue) · ⌃R armed")
        let fired = m.consume(at: now + 1) != nil
        print("⌃R -> \(m.phase(at: now + 1).rawValue) · read fired \(fired ? "once" : "NEVER") · ⌃R released")
        let again = m.consume(at: now + 2) != nil
        print("⌃R again -> \(again ? "READ AGAIN (bug)" : "nothing (already consumed)")")
        let offArmed = m.landed("the words", at: now + 3, speakEnabled: false)
        print("landed (speak off) -> \(m.phase(at: now + 3).rawValue) · ⌃R \(offArmed ? "ARMED (bug)" : "never armed")")
    }
}

/// The transient ⌃R claim. Register/unregister are idempotent and main-thread (like EscapeKey);
/// the Carbon hotkey exists ONLY between them, so there is no standing global ⌃R.
final class ReadBackKey {
    static let shared = ReadBackKey()
    private init() {}

    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    private var onPress: (() -> Void)?

    private static let sig = OSType(0x766F_7A52) // "vozR" — the voz-era signature family, like the bundle id
    private static let hotKeyID: UInt32 = 3      // distinct from ⌃V (Speak, id 1) and Escape (99)

    /// Claim ⌃R and route presses to `onPress`. A re-arm just swaps the handler.
    func register(_ onPress: @escaping () -> Void) {
        self.onPress = onPress
        installHandler()
        guard ref == nil else { return }
        let id = EventHotKeyID(signature: Self.sig, id: Self.hotKeyID)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey), id, GetApplicationEventTarget(), 0, &ref)
    }

    /// Release ⌃R back to the system. Idempotent.
    func unregister() {
        onPress = nil
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
    }

    /// Installed once, kept for the app's life — inert while no hotkey is registered.
    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Every hotkey-pressed handler on the app target sees every hotkey — return
        // eventNotHandledErr for anything not ours, or the ⌃V/Escape handlers starve (the
        // documented bug pattern in SpeakController/EscapeKey).
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if hk.signature == ReadBackKey.sig, hk.id == ReadBackKey.hotKeyID {
                DispatchQueue.main.async { ReadBackKey.shared.onPress?() }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &spec, nil, nil)
    }
}
