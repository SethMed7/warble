import XCTest
@testable import Dictate

/// The anti-hallucination filter — the mandatory second guard on engine output (whisper invents
/// phantom text on near-silent audio). Real words must always pass; known phantoms must not.
final class HallucinationTests: XCTestCase {
    func testRealTextPasses() {
        XCTAssertEqual(Hallucination.filter("ship the report today"), "ship the report today")
    }

    func testKnownPhantomsAreDropped() {
        XCTAssertEqual(Hallucination.filter("Thank you."), "")
        XCTAssertEqual(Hallucination.filter("[BLANK_AUDIO]"), "")
        XCTAssertEqual(Hallucination.filter("..."), "")
    }

    func testLoopedIdenticalLinesAreDropped() {
        XCTAssertEqual(Hallucination.filter("thanks\nthanks\nthanks"), "")
    }

    func testConsecutiveDuplicateLinesCollapse() {
        XCTAssertEqual(Hallucination.filter("one thing\none thing\nanother thing"),
                       "one thing\nanother thing")
    }

    func testLoneBracketedTagIsDropped() {
        XCTAssertEqual(Hallucination.filter("[music]"), "")
        XCTAssertEqual(Hallucination.filter("(silence)"), "")
    }

    func testBracketedRealSentenceSurvives() {
        XCTAssertEqual(Hallucination.filter("[see the attached notes]"), "[see the attached notes]")
    }
}
