import XCTest
@testable import Dictate

/// Dictate → read-back proofread (ROADMAP 0.5): the pure availability machine behind the
/// transient ⌃R claim — landed → available → expired/consumed, one-shot consumption, and the
/// per-mode gate (read-aloud off → never available). Everything here is synthetic-clock and
/// side-effect-free: no Carbon, no timers, no UserDefaults. The live wiring (the claim actually
/// registering/releasing, the Speak handoff) is by-hand (docs/testing.md); the story the CLI
/// prints for regression.sh (`--readback-state`) runs this exact machine.
final class ReadBackTests: XCTestCase {
    func testIdleUntilSomethingLands() {
        let m = ReadBackAvailability()
        XCTAssertEqual(m.phase(at: 0), .idle)
        var mm = m
        XCTAssertNil(mm.consume(at: 0), "nothing landed — nothing to read")
    }

    func testLandedArmsAndIsAvailableThroughTheGraceWindow() {
        var m = ReadBackAvailability()
        XCTAssertTrue(m.landed("ship the report", at: 100, speakEnabled: true), "speak on → ⌃R arms")
        XCTAssertEqual(m.phase(at: 100), .available)
        XCTAssertEqual(m.phase(at: 100 + ReadBackAvailability.graceSeconds - 0.01), .available,
                       "still available just inside the window")
    }

    func testExpiresExactlyAtTheGraceWindow() {
        var m = ReadBackAvailability()
        _ = m.landed("ship the report", at: 100, speakEnabled: true)
        XCTAssertEqual(m.phase(at: 100 + ReadBackAvailability.graceSeconds), .expired,
                       "the boundary itself is expired — the claim never outlives its stated window")
        XCTAssertNil(m.consume(at: 100 + ReadBackAvailability.graceSeconds), "an expired press reads nothing")
    }

    func testConsumeIsOneShot() {
        var m = ReadBackAvailability()
        _ = m.landed("ship the report", at: 0, speakEnabled: true)
        XCTAssertEqual(m.consume(at: 1), "ship the report", "the just-landed text, verbatim")
        XCTAssertEqual(m.phase(at: 1), .consumed)
        XCTAssertNil(m.consume(at: 2), "a second press reads nothing — the claim was spent")
    }

    func testSpeakOffNeverArms() {
        var m = ReadBackAvailability()
        XCTAssertFalse(m.landed("ship the report", at: 0, speakEnabled: false),
                       "per-mode law: read-aloud off → ⌃R never registers")
        XCTAssertEqual(m.phase(at: 0), .idle)
        XCTAssertNil(m.consume(at: 1))
    }

    func testEmptyTextNeverArms() {
        var m = ReadBackAvailability()
        XCTAssertFalse(m.landed("", at: 0, speakEnabled: true))
        XCTAssertEqual(m.phase(at: 0), .idle)
    }

    func testCancelWithdrawsAvailability() {
        var m = ReadBackAvailability()
        _ = m.landed("ship the report", at: 0, speakEnabled: true)
        m.cancel() // a new dictation started, or a mode turned off
        XCTAssertEqual(m.phase(at: 1), .idle)
        XCTAssertNil(m.consume(at: 1))
    }

    func testRelandingSupersedesWithTheNewText() {
        var m = ReadBackAvailability()
        _ = m.landed("first", at: 0, speakEnabled: true)
        XCTAssertTrue(m.landed("second", at: 5, speakEnabled: true))
        XCTAssertEqual(m.consume(at: 6), "second", "the newest landing owns the window")
    }

    func testRelandingAfterConsumptionArmsAgain() {
        var m = ReadBackAvailability()
        _ = m.landed("first", at: 0, speakEnabled: true)
        _ = m.consume(at: 1)
        XCTAssertTrue(m.landed("second", at: 2, speakEnabled: true))
        XCTAssertEqual(m.phase(at: 2), .available)
        XCTAssertEqual(m.consume(at: 3), "second")
    }

    func testLandingWithSpeakOffWithdrawsAPriorAvailability() {
        var m = ReadBackAvailability()
        _ = m.landed("first", at: 0, speakEnabled: true)
        XCTAssertFalse(m.landed("second", at: 1, speakEnabled: false),
                       "the mode went off between landings — nothing stays armed")
        XCTAssertEqual(m.phase(at: 1), .idle)
    }

    // MARK: the secure-field gate (ROADMAP 0.5 safety claim) — a spoken password must never be
    // read back aloud. `secure` defaults to false so every call site above is unaffected.

    func testSecureFieldNeverArmsEvenWithSpeakOn() {
        var m = ReadBackAvailability()
        XCTAssertFalse(m.landed("hunter2", at: 0, speakEnabled: true, secure: true),
                       "a secure (password) field must never arm ⌃R, even with read-aloud on")
        XCTAssertEqual(m.phase(at: 0), .idle)
        XCTAssertNil(m.consume(at: 1))
    }

    func testSecureLandingWithdrawsAPriorAvailability() {
        var m = ReadBackAvailability()
        _ = m.landed("first", at: 0, speakEnabled: true)
        XCTAssertFalse(m.landed("hunter2", at: 1, speakEnabled: true, secure: true),
                       "a secure dictation landing must withdraw whatever was armed before it")
        XCTAssertEqual(m.phase(at: 1), .idle)
    }
}
