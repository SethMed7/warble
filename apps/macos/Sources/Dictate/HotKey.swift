import AppKit

/// Global dictation triggers via NSEvent monitoring: the built-in **Fn (🌐) key** plus up to
/// three user bindings (right ⌘ / right ⌥ / F13–F19 / mouse buttons 3–10 — Bindings.swift).
/// Every trigger speaks the same two gestures — bindings are aliases of Fn, never modes:
///   • Hold — hold-to-talk: `onPress` once it's held past a short threshold, `onRelease` on lift.
///   • Double-tap (alone, quickly) — `onDoubleTap`: a hands-free toggle (start, then stop).
///
/// Hold and double-tap share one key, so we disambiguate by timing: a quick tap is never a hold
/// (recording only starts after `holdDelay`), and two clean taps inside `tapWindow` are the
/// double-tap. `keyDown` is watched so a modifier trigger used as a shortcut (Fn + arrow,
/// right-⌘ C) is told apart from a deliberate bare tap/hold and never triggers dictation. Global
/// monitoring needs Accessibility, which the app already has — and monitors are OBSERVERS by
/// construction: they can never consume or delay an event, so a bound key or button still does
/// whatever it normally does (pick ones your apps don't use). The callback stays O(1): at most
/// four machines, no allocation, no I/O.
///
/// Note: if macOS "Press 🌐 key to" is set to Start Dictation/Show Emoji, set it to **Do Nothing**
/// (System Settings ▸ Keyboard) so Fn is free for warble.
final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// `viaBinding` is false for the built-in Fn (its double-tap is gated by the menu's
    /// Hands-free toggle in DictateController) and true for a user binding's double-tap gesture —
    /// bound deliberately, so removing the binding is how it's turned off, not that toggle.
    var onDoubleTap: ((_ viaBinding: Bool) -> Void)?

    private var monitors: [Any] = []
    private var machines: [Machine] = []
    private var holdOwner: Machine? // the machine whose hold-to-talk is recording — one at a time

    /// True while the monitors are installed — asserted by tests so a test binary can prove it
    /// never leaves a monitor behind.
    var isRegistered: Bool { !monitors.isEmpty }

    // Timing shared by every trigger (the proven Fn values).
    private let holdDelay: TimeInterval = 0.18    // held this long to start — distinguishes hold from tap
    private let tapWindow: TimeInterval = 0.4
    private let minTapGap: TimeInterval = 0.08    // two edges closer than this are chatter, not a double-tap

    /// One trigger's gesture state — the original Fn state machine, one instance per trigger.
    private final class Machine {
        let trigger: BindingTrigger?  // nil = the built-in Fn
        let holds: Bool               // hold-to-talk gesture active for this trigger
        let doubleTaps: Bool          // double-tap gesture active for this trigger
        var isDown = false
        var tainted = false           // another key/modifier joined → a shortcut, not dictation
        var holdWork: DispatchWorkItem?
        // Double-tap bookkeeping (NSEvent.timestamp — monotonic seconds since boot).
        var lastTapAt: TimeInterval = 0
        var lastTapClean = false
        var cooldownUntil: TimeInterval = 0   // ignore taps briefly after a toggle (the gesture's tail)

        init(trigger: BindingTrigger?, holds: Bool, doubleTaps: Bool) {
            self.trigger = trigger
            self.holds = holds
            self.doubleTaps = doubleTaps
        }
        func cancelHold() { holdWork?.cancel(); holdWork = nil }
        /// Keyboard chords (⌘C…) taint the modifier triggers; F-keys and mouse buttons don't chord.
        var taintsOnKeyDown: Bool { trigger == nil || trigger?.isModifier == true }
    }

    func register() {
        guard monitors.isEmpty else { return } // idempotent: never stack monitors
        machines = Self.buildMachines(Bindings.shared.list)
        let mask = Self.mask(for: machines)
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e) }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e); return e }) {
            monitors.append(l)
        }
    }

    /// Tear the monitors down so every trigger is fully inert (used when dictation is toggled off).
    func unregister() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        machines.forEach { $0.cancelHold() }
        machines = []
        holdOwner = nil
    }

    /// Re-derive the trigger set from Bindings — the dashboard editor calls this after every edit,
    /// so changes apply live, no relaunch. A hold-to-talk session mid-flight is released cleanly
    /// first (its words deliver — product.md §4.10, never dropped). No-op while Dictate is off:
    /// the monitors stay down and the next register() reads the fresh list anyway.
    func reload() {
        guard !monitors.isEmpty else { return }
        if holdOwner != nil {
            holdOwner = nil
            DispatchQueue.main.async { self.onRelease?() }
        }
        unregister()
        register()
    }

    /// Fn is always present with both gestures (built in); each bound trigger gets one machine
    /// carrying whichever gestures its bindings declare.
    private static func buildMachines(_ bindings: [DictationBinding]) -> [Machine] {
        var machines = [Machine(trigger: nil, holds: true, doubleTaps: true)]
        var seen: [BindingTrigger] = []
        for b in bindings where !seen.contains(b.trigger) { seen.append(b.trigger) }
        for t in seen {
            machines.append(Machine(trigger: t,
                                    holds: bindings.contains { $0.trigger == t && $0.gesture == .hold },
                                    doubleTaps: bindings.contains { $0.trigger == t && $0.gesture == .doubleTap }))
        }
        return machines
    }

    /// The monitor mask grows only with the bindings that need it: no bindings = exactly the
    /// original Fn mask; keyUp joins for F-keys, otherMouse for mouse buttons.
    private static func mask(for machines: [Machine]) -> NSEvent.EventTypeMask {
        var mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if machines.contains(where: { $0.trigger?.fkeyKeyCode != nil }) { mask.insert(.keyUp) }
        if machines.contains(where: { $0.trigger?.mouseButtonNumber != nil }) {
            mask.formUnion([.otherMouseDown, .otherMouseUp])
        }
        return mask
    }

    private func machine(forKeyCode code: UInt16) -> Machine? {
        machines.first { $0.trigger?.fkeyKeyCode == code }
    }
    private func machine(forButton n: Int) -> Machine? {
        machines.first { $0.trigger?.mouseButtonNumber == n }
    }

    private func handle(_ event: NSEvent) {
        let t = event.timestamp
        switch event.type {
        case .keyDown:
            if let m = machine(forKeyCode: event.keyCode) {
                guard !event.isARepeat else { return }
                // An F-key pressed with a modifier held is a chord aimed at some app, not dictation
                // — and it taints any modifier trigger currently down, exactly like any other key.
                taintDownMachines(except: m)
                let mods = !event.modifierFlags
                    .intersection([.command, .option, .control, .shift, .capsLock]).isEmpty
                down(m, at: t, otherMods: mods)
            } else {
                taintDownMachines(except: nil) // trigger + a key = a shortcut, never dictation
            }
        case .keyUp:
            if let m = machine(forKeyCode: event.keyCode) { up(m, at: t) }
        case .otherMouseDown:
            // Buttons don't chord: no modifier taint (⌘-thumb-click while dictating is the app's
            // business — the monitor observes, never consumes).
            if let m = machine(forButton: event.buttonNumber) { down(m, at: t, otherMods: false) }
        case .otherMouseUp:
            if let m = machine(forButton: event.buttonNumber) { up(m, at: t) }
        case .flagsChanged:
            handleFlags(event, at: t)
        default:
            break
        }
    }

    /// The modifier triggers (Fn, right ⌘, right ⌥) live on flagsChanged: derive each machine's
    /// down state from the flags — Fn from the coarse .function flag (as ever), the right-side
    /// keys from their device-dependent bit (the coarse flag can't tell right from left).
    private func handleFlags(_ event: NSEvent, at t: TimeInterval) {
        let flags = event.modifierFlags
        for m in machines {
            let nowDown: Bool
            let taintSet: NSEvent.ModifierFlags
            if m.trigger == nil {
                nowDown = flags.contains(.function)
                taintSet = [.command, .option, .control, .shift, .capsLock]
            } else if let bit = m.trigger?.deviceBit, let own = m.trigger?.modifierFlag {
                nowDown = flags.rawValue & bit != 0
                taintSet = NSEvent.ModifierFlags([.command, .option, .control, .shift, .capsLock, .function])
                    .subtracting(own)
            } else {
                continue // key/mouse machines don't live on flags
            }
            let otherMods = !flags.intersection(taintSet).isEmpty
            if nowDown, !m.isDown {                // trigger pressed
                down(m, at: t, otherMods: otherMods)
            } else if nowDown, otherMods, m.isDown { // another modifier joined mid-hold → taint
                m.tainted = true
                m.cancelHold()
            } else if !nowDown, m.isDown {         // trigger released
                up(m, at: t)
            }
        }
    }

    /// A down edge: second clean tap inside the window → double-tap; otherwise maybe a hold.
    private func down(_ m: Machine, at t: TimeInterval, otherMods: Bool) {
        m.tainted = otherMods
        let gap = t - m.lastTapAt
        if holdOwner !== m, m.doubleTaps, m.lastTapClean, gap > minTapGap, gap < tapWindow, t >= m.cooldownUntil {
            // Second clean tap → hands-free toggle; don't also start a hold.
            m.lastTapAt = 0; m.lastTapClean = false; m.cooldownUntil = t + 0.6
            m.cancelHold()
            let viaBinding = m.trigger != nil
            DispatchQueue.main.async { self.onDoubleTap?(viaBinding) }
        } else if m.holds {
            scheduleHold(m)                        // maybe a hold — confirm after the threshold
        }
        m.isDown = true
    }

    /// An up edge: end the hold-to-talk if this machine owns it, else remember the tap.
    private func up(_ m: Machine, at t: TimeInterval) {
        m.cancelHold()
        if holdOwner === m {
            holdOwner = nil
            DispatchQueue.main.async { self.onRelease?() }
        } else if m.isDown {
            // A tap (released before the hold threshold) — remember it for double-tap detection.
            m.lastTapAt = t
            m.lastTapClean = !m.tainted
        }
        m.isDown = false
    }

    private func scheduleHold(_ m: Machine) {
        m.cancelHold()
        let w = DispatchWorkItem { [weak self, weak m] in
            guard let self, let m, m.isDown, !m.tainted,
                  self.holdOwner == nil,
                  self.machines.contains(where: { $0 === m }) // not retired by a reload meanwhile
            else { return }
            self.holdOwner = m
            self.onPress?()
        }
        m.holdWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: w)
    }

    /// Any plain keyDown while a modifier trigger is held = a shortcut in flight — taint it, so a
    /// pending hold never starts. (An active recording is untouched: taint only gates the start,
    /// exactly the original Fn discipline.)
    private func taintDownMachines(except spared: Machine?) {
        for m in machines where m !== spared && m.isDown && m.taintsOnKeyDown {
            m.tainted = true
            m.cancelHold()
        }
    }
}
