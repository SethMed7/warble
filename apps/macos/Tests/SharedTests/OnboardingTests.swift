import XCTest
@testable import Shared

/// The onboarding state machine (ROADMAP 0.4): step order, grant-one-reveal-next gating, the two
/// skip paths, the first-launch gate migration, and the post-macOS-update re-verify — all pure,
/// engine-free, permission-free. The rendered cards are proven separately by --render-onboarding
/// in scripts/regression.sh.
final class OnboardingFlowTests: XCTestCase {
    private func flow(mic: @escaping () -> Bool = { false },
                      ax: @escaping () -> Bool = { false }) -> OnboardingFlow {
        OnboardingFlow.standard(micGranted: mic, axGranted: ax)
    }

    func testStandardFlowOrderAndSkippability() {
        let f = flow()
        XCTAssertEqual(f.steps.map(\.id), ["welcome", "mic", "ax", "finish"])
        // Product law (product.md §4.5): every step is skippable, no exceptions.
        XCTAssertTrue(f.steps.allSatisfy(\.skippable))
    }

    func testWelcomeAndFinishAreAlwaysComplete() {
        let f = flow()
        XCTAssertTrue(f.steps.first { $0.id == "welcome" }!.isComplete())
        XCTAssertTrue(f.steps.first { $0.id == "finish" }!.isComplete())
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
        // Only the genuinely incomplete steps read as skipped; welcome/finish were never pending.
        XCTAssertEqual(f.skipped, ["mic", "ax"])
    }

    func testAdvancingThroughTheLastStepFinishes() {
        var f = flow(mic: { true }, ax: { true })
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
        f.skip() // ax skipped → lands on finish
        XCTAssertEqual(f.current?.id, "finish")
        XCTAssertTrue(f.canAdvance)
        XCTAssertTrue(f.advance())
        XCTAssertTrue(f.finished)
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
