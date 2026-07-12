import XCTest
@testable import Dictate

/// "Press enter" auto-send (ROADMAP 0.5): recognized ONLY in the final position of the cleaned
/// transcript, off by default, never touching a mid-sentence occurrence (product.md §4.5 — a
/// dictated instruction that happens to contain the words must survive verbatim). The pure
/// detector (`detectFinal`) is exercised directly with no UserDefaults, no AX, no events; the
/// toggle-aware `apply` is exercised against this test process's own UserDefaults domain (isolated
/// from the real app's `io.github.sethmed7.voz` domain by construction — a different bundle
/// entirely) and always restored. Storage (the "warble" defaults domain round-trip across
/// processes) and the Return keystroke are proven end to end by regression.sh's `autosend` check.
final class AutoSendTests: XCTestCase {
    // MARK: detectFinal — pure, no toggle involved

    func testFinalPositionMatchesPressEnter() {
        let r = AutoSend.detectFinal("ship the report press enter")
        XCTAssertTrue(r.matched)
        XCTAssertEqual(r.stripped, "ship the report")
        XCTAssertEqual(r.said, "press enter")
    }

    func testFinalPositionMatchesPressReturn() {
        let r = AutoSend.detectFinal("ship the report press return")
        XCTAssertTrue(r.matched)
        XCTAssertEqual(r.stripped, "ship the report")
        XCTAssertEqual(r.said, "press return")
    }

    func testCaseInsensitive() {
        XCTAssertTrue(AutoSend.detectFinal("PRESS ENTER").matched)
        XCTAssertTrue(AutoSend.detectFinal("Press Enter").matched)
        XCTAssertTrue(AutoSend.detectFinal("PrEsS rEtUrN").matched)
    }

    func testTrailingPunctuationTolerated() {
        for suffix in [".", "!", "?", ",", "...", "!!"] {
            let r = AutoSend.detectFinal("ship the report press enter\(suffix)")
            XCTAssertTrue(r.matched, "suffix \"\(suffix)\" should be tolerated")
            XCTAssertEqual(r.stripped, "ship the report")
        }
    }

    func testWholeDictationIsJustTheCommand() {
        let r = AutoSend.detectFinal("press enter")
        XCTAssertTrue(r.matched)
        XCTAssertEqual(r.stripped, "")
    }

    func testMultiLineDictationPreservesNewlinesBeforeTheCommand() {
        // A spoken "new line" survives as \n elsewhere in the transcript (Paster.swift) — the
        // command strip must not collapse it. Only the whitespace separating the command from the
        // rest is trimmed.
        let r = AutoSend.detectFinal("line one\nline two press enter")
        XCTAssertTrue(r.matched)
        XCTAssertEqual(r.stripped, "line one\nline two")
    }

    // MARK: mid-sentence negatives — left completely verbatim

    func testMidSentenceOccurrenceIsIgnored() {
        let r = AutoSend.detectFinal("please press enter and then keep typing")
        XCTAssertFalse(r.matched)
        XCTAssertEqual(r.stripped, "please press enter and then keep typing")
    }

    func testDescribingSomeoneElseSayingItIsIgnored() {
        let r = AutoSend.detectFinal("he told me to press enter but I ignored it")
        XCTAssertFalse(r.matched)
    }

    func testWordBoundaryNeverMatchesInsideAWord() {
        // "impress enter" ends in "enter" but the prior token core is "impress", not "press".
        XCTAssertFalse(AutoSend.detectFinal("don't impress enter").matched)
    }

    func testJustOneOfTheTwoWordsDoesNotMatch() {
        XCTAssertFalse(AutoSend.detectFinal("press").matched)
        XCTAssertFalse(AutoSend.detectFinal("enter").matched)
        XCTAssertFalse(AutoSend.detectFinal("press the button").matched)
    }

    func testEmptyTextDoesNotMatch() {
        XCTAssertFalse(AutoSend.detectFinal("").matched)
    }

    // MARK: apply — the toggle gate (product.md §4.5: off by default, never re-enables itself)

    private var savedDefault: Bool?
    override func setUp() {
        super.setUp()
        savedDefault = UserDefaults.standard.object(forKey: "autoSendEnabled") as? Bool
    }
    override func tearDown() {
        if let savedDefault {
            UserDefaults.standard.set(savedDefault, forKey: "autoSendEnabled")
        } else {
            UserDefaults.standard.removeObject(forKey: "autoSendEnabled")
        }
        super.tearDown()
    }

    func testDefaultsToOff() {
        UserDefaults.standard.removeObject(forKey: "autoSendEnabled")
        XCTAssertFalse(AutoSend.enabled, "absent -> off, like every other opt-in toggle in warble")
    }

    func testOffPastesVerbatimEvenWithThePhrase() {
        AutoSend.enabled = false
        let r = AutoSend.apply("ship the report press enter")
        XCTAssertFalse(r.send)
        XCTAssertEqual(r.pasted, "ship the report press enter", "no hint, no strip, no nag — product.md §4.6")
    }

    func testOnStripsAndReportsSend() {
        AutoSend.enabled = true
        let r = AutoSend.apply("ship the report press enter")
        XCTAssertTrue(r.send)
        XCTAssertEqual(r.pasted, "ship the report")
        XCTAssertEqual(r.said, "press enter")
    }

    func testOnButNoTrailingPhraseNeverSends() {
        AutoSend.enabled = true
        let r = AutoSend.apply("ship the report")
        XCTAssertFalse(r.send)
        XCTAssertEqual(r.pasted, "ship the report")
    }

    func testOnButMidSentenceNeverSends() {
        AutoSend.enabled = true
        let r = AutoSend.apply("please press enter and keep typing")
        XCTAssertFalse(r.send)
        XCTAssertEqual(r.pasted, "please press enter and keep typing")
    }

    // MARK: mayFireReturn — the final gate DictateController.deliver calls (pulled out so the
    // safety claim is a unit test, not just a comment): the Return keystroke fires only when the
    // phrase matched AND the field wasn't secure. A spoken password must never be submitted.

    func testMayFireReturnWhenMatchedAndNotSecure() {
        XCTAssertTrue(AutoSend.mayFireReturn(said: "press enter", secure: false))
    }

    func testMayFireReturnNeverFiresInASecureField() {
        XCTAssertFalse(AutoSend.mayFireReturn(said: "press enter", secure: true),
                        "a secure (password) field must never receive the Return keystroke, even when the phrase was said")
    }

    func testMayFireReturnNeverFiresWithoutThePhrase() {
        XCTAssertFalse(AutoSend.mayFireReturn(said: nil, secure: false))
        XCTAssertFalse(AutoSend.mayFireReturn(said: nil, secure: true))
    }
}
