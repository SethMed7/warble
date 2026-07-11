import XCTest
@testable import Shared

/// The onboarding state machine (ROADMAP 0.4): step order, grant-one-reveal-next gating, the two
/// skip paths, the first-launch gate migration, and the post-macOS-update re-verify — all pure,
/// engine-free, permission-free. The rendered cards are proven separately by --render-onboarding
/// in scripts/regression.sh.
final class OnboardingFlowTests: XCTestCase {
    private func flow(mic: @escaping () -> Bool = { false },
                      ax: @escaping () -> Bool = { false },
                      practice: @escaping () -> Bool = { false },
                      read: @escaping () -> Bool = { false }) -> OnboardingFlow {
        OnboardingFlow.standard(micGranted: mic, axGranted: ax,
                                practiceDone: practice, readDone: read)
    }

    /// Walk a flow to the step with `id` (skipping past everything before it).
    private func walked(_ f: OnboardingFlow, to id: String) -> OnboardingFlow {
        var f = f
        while let cur = f.current, cur.id != id {
            if !f.advance() { f.skip() }
        }
        return f
    }

    func testStandardFlowOrderAndSkippability() {
        let f = flow()
        XCTAssertEqual(f.steps.map(\.id), ["welcome", "mic", "ax", "meter", "practice", "read", "finish"])
        // Product law (product.md §4.5): every step is skippable, no exceptions.
        XCTAssertTrue(f.steps.allSatisfy(\.skippable))
    }

    func testDemonstrationStepsAreAlwaysComplete() {
        // welcome/meter/finish are demonstrations — Next never gates on them.
        let f = flow()
        for id in ["welcome", "meter", "finish"] {
            XCTAssertTrue(f.steps.first { $0.id == id }!.isComplete(), "\(id) should be constant-complete")
        }
    }

    func testGrantRevealsNext() {
        var granted = false
        var f = flow(mic: { granted })
        XCTAssertTrue(f.advance()) // welcome is always complete
        XCTAssertEqual(f.current?.id, "mic")
        XCTAssertFalse(f.canAdvance)
        XCTAssertFalse(f.advance()) // Next stays gated until the grant (or a skip)
        XCTAssertEqual(f.current?.id, "mic")
        granted = true // the poll sees the grant land…
        XCTAssertTrue(f.canAdvance) // …and Next enables
        XCTAssertTrue(f.advance())
        XCTAssertEqual(f.current?.id, "ax")
    }

    func testSkipForNowMovesOnWithoutTheGrant() {
        var f = flow()
        f.advance()
        XCTAssertEqual(f.current?.id, "mic")
        f.skip()
        XCTAssertEqual(f.current?.id, "ax")
        XCTAssertTrue(f.skipped.contains("mic"))
        XCTAssertFalse(f.finished)
    }

    func testSkipAllFinishesInOneCall() {
        var f = flow()
        f.skipAll()
        XCTAssertTrue(f.finished)
        XCTAssertNil(f.current)
        // Only the genuinely incomplete steps read as skipped; the demonstrations were never pending.
        XCTAssertEqual(f.skipped, ["mic", "ax", "practice", "read"])
    }

    func testAdvancingThroughTheLastStepFinishes() {
        var f = flow(mic: { true }, ax: { true }, practice: { true }, read: { true })
        while f.advance() {}
        XCTAssertTrue(f.finished)
        XCTAssertNil(f.current)
        XCTAssertTrue(f.skipped.isEmpty)
    }

    func testSkippedStepStaysAdvanceableOnRevisitSemantics() {
        // canAdvance honors a recorded skip even if the predicate still says incomplete.
        var f = flow()
        f.advance()
        f.skip() // mic skipped
        f.skip() // ax skipped → lands on meter (constant-complete)
        XCTAssertEqual(f.current?.id, "meter")
        XCTAssertTrue(f.canAdvance)
        XCTAssertTrue(f.advance()) // meter needs no skip
        XCTAssertEqual(f.current?.id, "practice")
        f.skip() // practice skipped
        XCTAssertEqual(f.current?.id, "read")
        f.skip() // read skipped
        XCTAssertEqual(f.current?.id, "finish")
        XCTAssertTrue(f.canAdvance)
        XCTAssertTrue(f.advance())
        XCTAssertTrue(f.finished)
    }

    func testPracticeGatesUntilARehearsalLands() {
        // ROADMAP 0.4 "guaranteed first success": Next on the practice card lights only when a
        // sandboxed dictation actually landed (the model's practiceResult), or on a skip.
        var landed = false
        var f = walked(flow(mic: { true }, ax: { true }, practice: { landed }), to: "practice")
        XCTAssertEqual(f.current?.id, "practice")
        XCTAssertFalse(f.canAdvance)
        XCTAssertFalse(f.advance())
        landed = true // the rehearsal lands…
        XCTAssertTrue(f.canAdvance) // …and Next lights
        XCTAssertTrue(f.advance())
        XCTAssertEqual(f.current?.id, "read")
    }

    func testReadGatesUntilARealReadHappens() {
        var read = false
        var f = walked(flow(mic: { true }, ax: { true }, practice: { true }, read: { read }), to: "read")
        XCTAssertEqual(f.current?.id, "read")
        XCTAssertFalse(f.canAdvance)
        read = true // ⌃V fired while the card was up
        XCTAssertTrue(f.advance())
        XCTAssertEqual(f.current?.id, "finish")
    }

    func testJumpBackReachesAnEarlierStepAndClearsItsSkip() {
        // The meter card's "Back to Microphone": backward jumps work and re-ask (the skip clears,
        // so Next gates on the real grant again).
        var f = flow()
        f.advance()
        f.skip() // mic skipped
        f.skip() // ax skipped → meter
        XCTAssertEqual(f.current?.id, "meter")
        XCTAssertTrue(f.jump(to: "mic"))
        XCTAssertEqual(f.current?.id, "mic")
        XCTAssertFalse(f.skipped.contains("mic"))
        XCTAssertFalse(f.canAdvance) // gated on the grant again — a revisit is a re-ask
    }

    func testJumpNeverGoesForwardOrToUnknownSteps() {
        var f = flow()
        f.advance() // at mic
        XCTAssertFalse(f.jump(to: "read"), "forward jumps would bypass grant-one-reveal-next")
        XCTAssertFalse(f.jump(to: "nope"))
        XCTAssertEqual(f.current?.id, "mic")
        f.skipAll()
        XCTAssertFalse(f.jump(to: "welcome"), "a finished flow has nowhere to jump")
    }
}

final class OnboardingGateTests: XCTestCase {
    func testFreshInstallShowsOnce() {
        XCTAssertTrue(OnboardingGate.shouldShow(didShowOnboarding: false, legacyDidShowWelcome: false))
    }

    func testExistingInstallNeverSeesTheTour() {
        // The migration: a pre-0.4 install has didShowWelcome set — the tour must not appear on update.
        XCTAssertFalse(OnboardingGate.shouldShow(didShowOnboarding: false, legacyDidShowWelcome: true))
    }

    func testShownOnceNeverAgain() {
        XCTAssertFalse(OnboardingGate.shouldShow(didShowOnboarding: true, legacyDidShowWelcome: false))
        XCTAssertFalse(OnboardingGate.shouldShow(didShowOnboarding: true, legacyDidShowWelcome: true))
    }
}

final class PermissionReverifyTests: XCTestCase {
    func testSameBuildNeverNotices() {
        // A by-hand revocation on the same OS build is the user's choice — never surfaced.
        XCTAssertEqual(PermissionReverify.revoked(lastBuild: "23E224", currentBuild: "23E224",
                                                  wasGranted: ["mic", "ax"], nowGranted: []), [])
    }

    func testFirstSightingNeverNotices() {
        XCTAssertEqual(PermissionReverify.revoked(lastBuild: nil, currentBuild: "23E224",
                                                  wasGranted: ["mic"], nowGranted: []), [])
    }

    func testUpdateRevocationIsNamed() {
        XCTAssertEqual(PermissionReverify.revoked(lastBuild: "23E224", currentBuild: "23F79",
                                                  wasGranted: ["mic", "ax"], nowGranted: ["mic"]), ["ax"])
    }

    func testUpdateRevokingBothNamesBothSorted() {
        XCTAssertEqual(PermissionReverify.revoked(lastBuild: "23E224", currentBuild: "23F79",
                                                  wasGranted: ["mic", "ax"], nowGranted: []), ["ax", "mic"])
    }

    func testUpdateWithGrantsIntactStaysQuiet() {
        XCTAssertEqual(PermissionReverify.revoked(lastBuild: "23E224", currentBuild: "23F79",
                                                  wasGranted: ["mic", "ax"], nowGranted: ["mic", "ax"]), [])
    }

    func testNeverGrantedNeverNotices() {
        XCTAssertEqual(PermissionReverify.revoked(lastBuild: "23E224", currentBuild: "23F79",
                                                  wasGranted: [], nowGranted: []), [])
    }
}
