import XCTest
@testable import Dictate

/// Spoken spelling (SpellOut): a cued letter run replaces the heard word and is learned; without a
/// cue, single letters in ordinary speech are never touched (the safety rule in SpellOut's header).
final class SpellOutTests: XCTestCase {
    func testCuedSpellingReplacesAndLearns() {
        let r = SpellOut.process("what's going on Dhaval that's D H A V A L with your work today")
        XCTAssertEqual(r.text, "what's going on Dhaval with your work today")
        XCTAssertEqual(r.learned.count, 0) // heard == spelled → nothing to learn (casing-only)
    }

    func testMisrecognitionIsLearned() {
        let r = SpellOut.process("say hi to deval that's D H A V A L today")
        XCTAssertEqual(r.text, "say hi to Dhaval today")
        XCTAssertEqual(r.learned.count, 1)
        XCTAssertEqual(r.learned.first?.from, "deval")
        XCTAssertEqual(r.learned.first?.to, "Dhaval")
    }

    func testUncuedLettersAreLeftAlone() {
        let r = SpellOut.process("we sell a b c batteries")
        XCTAssertEqual(r.text, "we sell a b c batteries")
        XCTAssertTrue(r.learned.isEmpty)
    }

    func testCapsCueForcesUppercase() {
        let r = SpellOut.process("the acronym msd spelled capital M S D please")
        XCTAssertEqual(r.text, "the acronym MSD please")
    }

    func testHeardAllCapsWordKeepsAcronymCase() {
        let r = SpellOut.process("ping MSD that's M S D now")
        XCTAssertEqual(r.text, "ping MSD now")
        XCTAssertTrue(r.learned.isEmpty) // same letters → casing-only, never learned
    }

    func testSingleLetterRunNeedsTwoLetters() {
        let r = SpellOut.process("grade it that's a fine result")
        XCTAssertEqual(r.text, "grade it that's a fine result")
        XCTAssertTrue(r.learned.isEmpty)
    }
}
