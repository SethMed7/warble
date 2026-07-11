import XCTest
@testable import Dictate

/// The long-session cap math (HoldCap). The live warn→stop machine (HoldCapClock) is proven by
/// the CLI's --hold-cap-sim under a compressed cap — a unit test here would just re-pay its
/// wall-clock seconds, so only the pure math lives in this target.
///
/// These tests assume WARBLE_MAX_HOLD_SECS is NOT set (regression.sh runs `swift test` bare);
/// ProcessInfo.environment is snapshotted per process, so the seam can't be toggled in-test.
final class HoldCapTests: XCTestCase {
    func testDefaultCapIsTwentyMinutes() {
        XCTAssertEqual(HoldCap.maxSeconds, 20 * 60)
        XCTAssertEqual(HoldCap.label, "20-minute")
    }

    func testWarnWindowIsOneMinuteForRealCaps() {
        XCTAssertEqual(HoldCap.warnWindow(for: 1200), 60)
        XCTAssertEqual(HoldCap.warnWindow(for: 120), 60)
    }

    func testWarnWindowHalvesForTinyDebugCaps() {
        // The warning must PRECEDE the stop, never swallow the whole session.
        XCTAssertEqual(HoldCap.warnWindow(for: 6), 3)
        XCTAssertEqual(HoldCap.warnWindow(for: 4), 2)
    }

    func testStopCopyNamesTheCap() {
        XCTAssertEqual(DictateError.holdCapReached.message, "hit the 20-minute cap")
    }
}
