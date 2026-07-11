import XCTest
@testable import Dictate

/// The Swift twin of core/clean.test.ts, case for case. BasicCleaner must stay rule-identical to
/// core/clean.ts (see its header) — running the SAME acceptance suite against both is what keeps
/// the twins from drifting. If a case changes here, change it in clean.test.ts too.
final class BasicCleanerTests: XCTestCase {
    private func clean(_ s: String) -> String { BasicCleaner.cleaned(s) }

    // MARK: acceptance

    func testNumeralCorrectionViaActually() {
        XCTAssertEqual(clean("give me 2 actually 3 bunnies"), "give me 3 bunnies")
    }

    func testFillersAndDuplicateWords() {
        XCTAssertEqual(clean("um so like like I was thinking uh maybe we ship it"),
                       "so like I was thinking maybe we ship it")
    }

    func testNameCorrectionViaIMean() {
        XCTAssertEqual(clean("send it to John I mean Jane"), "send it to Jane")
    }

    func testNumberWordCorrectionViaNoWait() {
        XCTAssertEqual(clean("set a timer for five no wait ten minutes"),
                       "set a timer for ten minutes")
    }

    func testScratchThatDropsThePreviousClause() {
        XCTAssertEqual(clean("do the report scratch that do the deck"), "do the deck")
    }

    // MARK: fillers

    func testRemovesStandaloneFillersOnly() {
        XCTAssertEqual(clean("uhh er hmm mhm okay erm ah done"), "okay done")
    }

    func testDoesNotEatWordsContainingFillerLetters() {
        XCTAssertEqual(clean("the umbrella is ahead"), "the umbrella is ahead")
    }

    func testRemovesBareYouKnowSetOffByPunctuation() {
        XCTAssertEqual(clean("it was, you know, fine"), "it was, fine")
    }

    func testRemovesDanglingYouKnowAtTheEnd() {
        XCTAssertEqual(clean("it was great you know"), "it was great")
    }

    func testKeepsYouKnowWhenItCarriesMeaning() {
        XCTAssertEqual(clean("you know the answer"), "you know the answer")
    }

    func testRemovesHumVariants() {
        XCTAssertEqual(clean("uhm mmm hmmm mhmm okay then"), "okay then")
    }

    func testKeepsMMItReadsAsMillimetres() {
        XCTAssertEqual(clean("a 3 mm gap"), "a 3 mm gap")
    }

    // MARK: meaning preservation

    func testIdiomaticPairChainsStayVerbatim() {
        XCTAssertEqual(clean("it happened again and again and again"),
                       "it happened again and again and again")
        XCTAssertEqual(clean("we walked two by two by two"), "we walked two by two by two")
        XCTAssertEqual(clean("we tried again and again and failed"),
                       "we tried again and again and failed")
    }

    func testSpokenDigitRunsStayVerbatim() {
        XCTAssertEqual(clean("zero four zero four two"), "zero four zero four two")
    }

    func testTwoWordFalseStartsAreLeftForTheLLMPass() {
        XCTAssertEqual(clean("I want I want to go"), "I want I want to go")
    }

    // MARK: unicode

    func testMixedNormalizationDuplicatesCollapseOutputInNFC() {
        // NFC "caf\u{e9}" then NFD "cafe\u{301}" — the same word in two encodings.
        XCTAssertEqual(clean("caf\u{e9} cafe\u{301} forever"), "caf\u{e9} forever")
    }

    func testCombiningMarksSurviveInsideWords() {
        XCTAssertEqual(clean("el ni\u{f1}o esta bien"), "el ni\u{f1}o esta bien")
    }

    // MARK: corrections

    func testWaitNoBetweenNumberWords() {
        XCTAssertEqual(clean("grab six wait no nine apples"), "grab nine apples")
    }

    func testMakeThatBetweenNumberWords() {
        XCTAssertEqual(clean("give me two make that three"), "give me three")
    }

    func testRatherBetweenPlainTokens() {
        XCTAssertEqual(clean("paint it blue rather green"), "paint it green")
    }

    func testMarkerStaysWhenShapesDiffer() {
        XCTAssertEqual(clean("I actually like it"), "I actually like it")
    }

    func testMarkerAtTheStartStays() {
        XCTAssertEqual(clean("actually let's go"), "actually let's go")
    }

    func testScratchThatRespectsSentenceBoundaries() {
        XCTAssertEqual(clean("ship it today. do the report scratch that do the deck"),
                       "ship it today. do the deck")
    }

    // MARK: duplicates

    func testCollapsesImmediateRepeatsCaseInsensitively() {
        XCTAssertEqual(clean("the The cat"), "the cat")
    }

    func testDoesNotCollapseAcrossASentenceBoundary() {
        XCTAssertEqual(clean("stop. stop right there"), "stop. stop right there")
    }

    func testHadHadStillCollapsesViaTheSingleWordRule() {
        XCTAssertEqual(clean("he had had a rough week"), "he had a rough week")
    }

    // MARK: tidy

    func testCollapsesWhitespaceAndFixesSpaceBeforePunctuation() {
        XCTAssertEqual(clean("  hello ,  world  !"), "hello, world!")
    }

    func testCapitalizesOnlyWhenTheRawTextDid() {
        XCTAssertEqual(clean("Um hello there"), "Hello there")
        XCTAssertEqual(clean("um hello there"), "hello there")
    }

    func testEmptyAndFillerOnlyInput() {
        XCTAssertEqual(clean(""), "")
        XCTAssertEqual(clean("um uh hmm"), "")
    }
}
