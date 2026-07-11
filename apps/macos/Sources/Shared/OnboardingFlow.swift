import Foundation

/// The onboarding card flow's brain (ROADMAP 0.4 "sequential permission cards") — pure logic, no
/// AppKit, so `swift test` can prove the skip paths, gating, and migration headlessly. It lives in
/// Shared (not the executable target) because the test target can't import an executable; the
/// cards in WelcomeWindow render whatever this machine says.
///
/// The law it encodes (product.md §4.5/§4.6): EVERY step is skippable, skipping the whole flow is
/// always one click (`skipAll`), and the flow never reappears uninvited (`OnboardingGate`).
public struct OnboardingStep {
    public let id: String
    public let title: String
    /// Always true today — the field exists so the flow can never quietly grow a hostage step.
    public let skippable: Bool
    /// Live completion predicate (permission granted, demo done…), re-evaluated on demand — the
    /// UI polls it while the step's card is visible so a grant flips the card immediately.
    public let isComplete: () -> Bool

    public init(id: String, title: String, skippable: Bool = true, isComplete: @escaping () -> Bool) {
        self.id = id
        self.title = title
        self.skippable = skippable
        self.isComplete = isComplete
    }
}

/// Ordered steps + a cursor. A value type: the UI holds it as @Published state, so every
/// mutation republishes and the current card re-renders.
public struct OnboardingFlow {
    public private(set) var steps: [OnboardingStep]
    public private(set) var index = 0
    public private(set) var skipped: Set<String> = []
    /// True once the user moved past the last card (Done, or the one-click skip).
    public private(set) var finished = false

    public init(steps: [OnboardingStep]) { self.steps = steps }

    public var current: OnboardingStep? { finished ? nil : steps[index] }
    public var isLast: Bool { index == steps.count - 1 }

    /// Grant-one-reveal-next: the Next affordance enables when the step completes OR was skipped.
    public var canAdvance: Bool {
        guard let step = current else { return false }
        return step.isComplete() || skipped.contains(step.id)
    }

    /// Move to the next card (finishing on the last). Guarded by canAdvance so the machine is
    /// safe even if a UI ever forgets to disable its Next button.
    @discardableResult
    public mutating func advance() -> Bool {
        guard !finished, canAdvance else { return false }
        step()
        return true
    }

    /// "Skip for now": mark the current step skipped and move on without it.
    public mutating func skip() {
        guard let cur = current, cur.skippable else { return }
        skipped.insert(cur.id)
        step()
    }

    /// Jump BACK to an earlier step — the never-a-dead-end affordance: the meter card (mic
    /// skipped) and the read card (accessibility skipped) offer the permission card again in one
    /// click. Backward only, so a jump can never bypass grant-one-reveal-next gating; the
    /// target's recorded skip is cleared — revisiting a card is deliberately re-asking.
    @discardableResult
    public mutating func jump(to id: String) -> Bool {
        guard !finished, let i = steps.firstIndex(where: { $0.id == id }), i < index else { return false }
        index = i
        skipped.remove(id)
        return true
    }

    /// The one-click whole-flow skip ("Skip tour"): everything not already complete is skipped.
    public mutating func skipAll() {
        guard !finished else { return }
        for s in steps[index...] where !s.isComplete() { skipped.insert(s.id) }
        finished = true
    }

    private mutating func step() {
        if isLast { finished = true } else { index += 1 }
    }

    /// The 0.4 flow, in order: welcome → one permission per card (mic, accessibility) → the
    /// guaranteed-first-success arc (live meter → sandboxed practice dictation → read-aloud demo)
    /// → finish in the user's own app. Speech Recognition is deliberately NOT a card — only the
    /// Apple-fallback engine needs it, and it prompts contextually (the README's permission
    /// contract). meter/finish are demonstrations (constant-complete: Next never gates on them);
    /// practice/read complete when their real feature actually fired — the injected predicates
    /// are the UI's live "a rehearsal landed" / "a read happened while the card was up" state.
    public static func standard(micGranted: @escaping () -> Bool,
                                axGranted: @escaping () -> Bool,
                                practiceDone: @escaping () -> Bool = { false },
                                readDone: @escaping () -> Bool = { false }) -> OnboardingFlow {
        OnboardingFlow(steps: [
            OnboardingStep(id: "welcome", title: "Welcome to warble") { true },
            OnboardingStep(id: "mic", title: "Microphone", isComplete: micGranted),
            OnboardingStep(id: "ax", title: "Accessibility", isComplete: axGranted),
            OnboardingStep(id: "meter", title: "It hears you") { true },
            OnboardingStep(id: "practice", title: "Try a dictation", isComplete: practiceDone),
            OnboardingStep(id: "read", title: "Hear it back", isComplete: readDone),
            OnboardingStep(id: "finish", title: "Your own apps") { true },
        ])
    }
}

/// The first-launch gate. `didShowOnboarding` is 0.4's key; `didShowWelcome` is the pre-0.4
/// static welcome card's key — honoring it is the migration that keeps an existing install
/// (which has it set) from ever seeing the tour uninvited on update. Fresh installs have
/// neither → the tour shows exactly once.
public enum OnboardingGate {
    public static func shouldShow(didShowOnboarding: Bool, legacyDidShowWelcome: Bool) -> Bool {
        !didShowOnboarding && !legacyDidShowWelcome
    }
}

/// Post-macOS-update permission re-verify (ROADMAP 0.4): macOS updates are documented to silently
/// revoke Accessibility. The decision core, pure: a permission warrants a (quiet) notice only when
/// the OS build changed AND the permission flipped granted → not granted. Same build → never (a
/// by-hand revocation is the user's choice — product.md §4.5); first sighting (no stored build) →
/// never. Sorted so callers and tests see a stable order.
public enum PermissionReverify {
    public static func revoked(lastBuild: String?, currentBuild: String,
                               wasGranted: Set<String>, nowGranted: Set<String>) -> [String] {
        guard let last = lastBuild, last != currentBuild else { return [] }
        return wasGranted.subtracting(nowGranted).sorted()
    }
}
