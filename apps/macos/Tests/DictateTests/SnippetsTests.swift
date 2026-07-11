import XCTest
@testable import Dictate

/// Snippets (ROADMAP 0.5): spoken trigger phrase → local text expansion, applied AFTER cleanup +
/// the dictionary, BEFORE paste. These exercise the pure matcher (`Snippets.expand(_:using:)`) and
/// the pure key-normalization helper directly against in-memory values — no disk, no WARBLE_HOME —
/// the same split ResumableFetch and HoldCap use to keep environment-dependent code out of the
/// unit-test target (ProcessInfo.environment is snapshotted per process, so an env-var seam can't
/// be toggled mid-test; see HoldCapTests). Storage itself (WARBLE_HOME relocation, persistence,
/// 0600) is proven by regression.sh's `--expand`/`--snippet-set` checks, which spawn a real
/// process per case.
final class SnippetsTests: XCTestCase {
    func testNoSnippetsIsVerbatimPassthrough() {
        // product.md §4.4: nothing acts on the user's words unless they've defined a snippet.
        XCTAssertEqual(Snippets.expand("um so the the report", using: [:]), "um so the the report")
    }

    func testTriggerAloneReplacesTheWholeDictation() {
        let snippets = ["sign off": "Best,\nSeth"]
        XCTAssertEqual(Snippets.expand("sign off", using: snippets), "Best,\nSeth")
        XCTAssertEqual(Snippets.expand("Sign Off", using: snippets), "Best,\nSeth") // case-insensitive
    }

    func testTriggerInsideALongerDictationReplacesOnlyItsSpan() {
        let snippets = ["my address": "123 Main St"]
        XCTAssertEqual(Snippets.expand("please send it to my address today", using: snippets),
                       "please send it to 123 Main St today")
    }

    func testWordBoundariesNeverMatchInsideAWord() {
        let snippets = ["cat": "feline"]
        XCTAssertEqual(Snippets.expand("category", using: snippets), "category") // no partial-word match
        XCTAssertEqual(Snippets.expand("the cat sat", using: snippets), "the feline sat")
    }

    func testLongestMatchingTriggerWins() {
        let snippets = ["see you": "cya-short", "see you soon": "cya-later"]
        XCTAssertEqual(Snippets.expand("see you soon", using: snippets), "cya-later")
        XCTAssertEqual(Snippets.expand("see you tomorrow", using: snippets), "cya-short tomorrow")
    }

    func testNoRecursiveExpansion() {
        // "foo" expands to text that itself contains another trigger's words ("bar") — that must
        // NOT be expanded again; matching runs once, over the original text only.
        let snippets = ["foo": "bar baz", "bar": "QUX"]
        XCTAssertEqual(Snippets.expand("foo", using: snippets), "bar baz")
    }

    func testCaseInsensitiveMatch() {
        // Storage keys are already-lowercased (Snippets.set lowercases before storing); the
        // matcher must still find them against any casing in the transcript.
        let snippets = ["my address": "123 Main St"]
        XCTAssertEqual(Snippets.expand("MY ADDRESS is here", using: snippets), "123 Main St is here")
    }

    func testMultiLineExpansionSurvivesVerbatim() {
        let snippets = ["my sig": "Best,\nSeth\nwarble"]
        XCTAssertEqual(Snippets.expand("my sig", using: snippets), "Best,\nSeth\nwarble")
    }

    func testTwoNonOverlappingTriggersBothExpandInOnePass() {
        let snippets = ["my address": "123 Main St", "sign off": "Best,\nSeth"]
        XCTAssertEqual(Snippets.expand("my address, then sign off", using: snippets),
                       "123 Main St, then Best,\nSeth")
    }

    // MARK: normalizeKey — the storage-key hygiene `set()`/`load()` both route through

    func testNormalizeKeyLowercasesTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(Snippets.normalizeKey("  Sign   Off  "), "sign off")
        XCTAssertEqual(Snippets.normalizeKey("My Address"), "my address")
    }

    func testNormalizeKeyMakesWhitespaceVariantsCollide() {
        // Without this, "my address" and "my  address" (stray double space) could coexist as
        // distinct dict keys that build the IDENTICAL match pattern — a tie whose winner would
        // depend on Dictionary's unstable iteration order. Routing both through the same key
        // means there's only ever one entry to begin with.
        XCTAssertEqual(Snippets.normalizeKey("my  address"), Snippets.normalizeKey("my address"))
    }
}
