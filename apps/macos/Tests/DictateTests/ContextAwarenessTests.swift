import XCTest
@testable import Dictate

/// Local-only context awareness (ROADMAP 0.6) — the capture half's pure logic: the category
/// derivation, the two bounds (last ~200 words captured, ≤12-word preview persisted), and the two
/// zero-gates (toggle off → nothing; secure field → nothing at all). The record's privacy claim
/// is asserted STRUCTURALLY: ContextRecord's JSON is exactly {app, category, words, preview} and
/// a 13th word is unencodable, because the only initializer derives the capped preview — no field
/// can hold the full text. The live AX read (captureLive against a real focused app) is by-hand
/// (docs/testing.md); the cross-process toggle + gate story is regression.sh's `context` check
/// (--context-sim).
final class ContextAwarenessTests: XCTestCase {
    // MARK: categorize — a small static map, a keyword fallback, one AXTextArea nudge

    func testKnownBundleIdsMapToTheirCategory() {
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "com.apple.mail"), .mail)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "com.tinyspeck.slackmacgap"), .chat)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "com.googlecode.iterm2"), .editor)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "com.apple.dt.Xcode"), .editor)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "com.apple.iWork.Pages"), .document)
    }

    func testKeywordFallbackCategorizesUnknownBundleIds() {
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "io.example.SuperMail"), .mail)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "org.example.chatterbox"), .chat)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "io.example.megaterm"), .editor)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "io.example.notesapp"), .document)
    }

    func testUnknownBundleIdIsOther() {
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "com.example.mystery"), .other)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: nil), .other)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: ""), .other)
    }

    func testTextAreaNudgesOnlyOtherToDocument() {
        // The one AX-role heuristic: an unplaceable app whose focused element is a multi-line
        // text area is being written in like a document…
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "com.example.mystery",
                                                   focusedRole: "AXTextArea"), .document)
        // …but a known category is never overridden, and other roles never nudge.
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "com.tinyspeck.slackmacgap",
                                                   focusedRole: "AXTextArea"), .chat)
        XCTAssertEqual(ContextAwareness.categorize(bundleId: "com.example.mystery",
                                                   focusedRole: "AXTextField"), .other)
    }

    // MARK: clip — the word cap keeps the END of the value (nearest the cursor when composing)

    func testClipKeepsTheLast200Words() {
        let text = (1...250).map { "w\($0)" }.joined(separator: " ")
        let toks = ContextAwareness.clip(text).split(separator: " ")
        XCTAssertEqual(toks.count, 200)
        XCTAssertEqual(toks.first, "w51", "the cap must keep the END of the value — nearest the cursor")
        XCTAssertEqual(toks.last, "w250")
    }

    func testClipUnderTheCapIsUntouched() {
        XCTAssertEqual(ContextAwareness.clip("hello there\nworld"), "hello there\nworld")
    }

    // MARK: capture — the pure gate (off-zero + secure-zero)

    func testCaptureOffIsZero() {
        XCTAssertNil(ContextAwareness.capture(enabled: false, secure: false,
                                              bundleId: "com.apple.mail", name: "Mail",
                                              text: "dear team", focusedRole: nil),
                     "off must capture nothing — not app, not category, not a word")
    }

    func testCaptureSecureIsZero() {
        XCTAssertNil(ContextAwareness.capture(enabled: true, secure: true,
                                              bundleId: "com.apple.mail", name: "Mail",
                                              text: "hunter2", focusedRole: nil),
                     "a secure field must capture NOTHING at all, even with the toggle on")
    }

    func testCaptureWithNoReadableTextStillKnowsTheApp() {
        // Apps that expose nothing to AX degrade to an app-identity-only capture: category still
        // works (that's per-app tone), but zero words were read and the note says so.
        let c = ContextAwareness.capture(enabled: true, secure: false,
                                         bundleId: "com.apple.mail", name: "Mail",
                                         text: nil, focusedRole: nil)
        XCTAssertEqual(c?.category, .mail)
        XCTAssertEqual(c?.text, "")
        let r = c.map { ContextRecord($0) }
        XCTAssertEqual(r?.words, 0)
        XCTAssertEqual(r?.preview, "")
    }

    // MARK: the toggle — off by default (product.md §4.5)

    private var savedToggle: Bool?
    override func setUp() {
        super.setUp()
        savedToggle = UserDefaults.standard.object(forKey: "contextAwareness") as? Bool
    }
    override func tearDown() {
        if let savedToggle {
            UserDefaults.standard.set(savedToggle, forKey: "contextAwareness")
        } else {
            UserDefaults.standard.removeObject(forKey: "contextAwareness")
        }
        super.tearDown()
    }

    func testToggleDefaultsOff() {
        UserDefaults.standard.removeObject(forKey: "contextAwareness")
        XCTAssertFalse(ContextAwareness.enabled, "absent -> off: context awareness is opt-in")
    }

    // MARK: ContextRecord — the bounded note (the preview cap is structural)

    private func record(words n: Int, app: String = "Mail", bundleId: String = "com.apple.mail") -> ContextRecord {
        let text = (1...n).map { "w\($0)" }.joined(separator: " ")
        return ContextRecord(CapturedContext(appBundleId: bundleId, appName: app,
                                             category: .mail, text: text))
    }

    func testPreviewCapsAtTwelveWordsWithATruncationMark() {
        let r = record(words: 20)
        XCTAssertEqual(r.words, 20)
        XCTAssertEqual(r.preview, "w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12…")
    }

    func testShortPreviewCarriesNoMark() {
        XCTAssertEqual(record(words: 3).preview, "w1 w2 w3")
        XCTAssertEqual(record(words: 12).preview, "w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12")
    }

    func testRecordJSONSchemaIsExactlyAppCategoryWordsPreview() throws {
        let data = try JSONEncoder().encode(record(words: 20))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["app", "category", "words", "preview"],
                       "the record has no field that could hold the full text")
        XCTAssertEqual(obj["app"] as? String, "Mail")
        XCTAssertEqual(obj["category"] as? String, "mail")
        XCTAssertEqual(obj["words"] as? Int, 20)
    }

    func testThirteenthWordIsUnencodable() throws {
        // Structural, not behavioral: the only initializer derives the ≤12-word preview, so no
        // matter what was captured, word 13 onward cannot appear anywhere in the encoded record.
        let json = String(decoding: try JSONEncoder().encode(record(words: 200)), as: UTF8.self)
        XCTAssertTrue(json.contains("w12…"))
        XCTAssertFalse(json.contains("w13"), "the 13th captured word must have no encodable form")
        XCTAssertFalse(json.contains("w200"))
    }

    // MARK: the apply half (ROADMAP 0.6) — the polish prompt's category hint + the verbatim gate
    // (The deterministic tone rules themselves live in BasicCleanerTests, twin-for-twin with
    // clean.test.ts; the end-to-end leg order is regression.sh's context-apply check.)

    func testPromptWithoutACategoryIsByteIdenticalToTheBase() {
        // The golden no-change at the prompt level: with context off (category nil) — or an app
        // warble can't place (`other`) — the polish path is untouched, byte for byte.
        XCTAssertEqual(LLMPolish.prompt(LLMPolish.systemPrompt, category: nil), LLMPolish.systemPrompt)
        XCTAssertEqual(LLMPolish.prompt(LLMPolish.systemPromptHigh, category: .other), LLMPolish.systemPromptHigh)
    }

    func testPromptGainsExactlyOneHintLinePerCategory() {
        for category in [AppCategory.mail, .chat, .editor, .document] {
            let p = LLMPolish.prompt(LLMPolish.systemPrompt, category: category)
            XCTAssertTrue(p.hasPrefix(LLMPolish.systemPrompt), "the hint is additive — the base prompt is untouched")
            let added = p.dropFirst(LLMPolish.systemPrompt.count)
            XCTAssertTrue(added.hasPrefix("\nDestination: \(category.rawValue)"),
                          "one line naming the destination (got \"\(added)\")")
            XCTAssertEqual(added.filter { $0 == "\n" }.count, 1, "exactly one added line")
        }
    }

    func testNoneLevelStaysVerbatimEvenWithACategory() {
        // The verbatim law (product.md §4.4): at level None nothing is shaped — tone rules included.
        XCTAssertEqual(Cleaners.cleaner(at: .none, for: "on my way.", category: .chat).clean("on my way."),
                       "on my way.")
    }

    // MARK: DictationEvent — the record rides the history line; old lines still decode

    func testDictationEventRoundTripsTheContextRecord() throws {
        let e = DictationEvent(id: "c", ts: 4, day: "2026-07-11", text: "hi there", raw: nil,
                               words: 2, durationMs: 900, appBundleId: "com.apple.mail",
                               appName: "Mail", engine: "test", kind: "dictate", status: nil,
                               context: record(words: 20))
        let back = try JSONDecoder().decode(DictationEvent.self, from: try JSONEncoder().encode(e))
        XCTAssertEqual(back.context?.app, "Mail")
        XCTAssertEqual(back.context?.category, "mail")
        XCTAssertEqual(back.context?.words, 20)
        XCTAssertEqual(back.context?.preview, "w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12…")
    }

    func testPre06HistoryLinesStillDecode() throws {
        let legacy = #"{"id":"x","ts":1,"day":"2026-07-11","text":"so the report","words":3,"durationMs":900,"engine":"test","kind":"dictate"}"#
        let e = try JSONDecoder().decode(DictationEvent.self, from: Data(legacy.utf8))
        XCTAssertNil(e.context, "a pre-0.6 line has no context note — it must decode as nil")
    }
}
