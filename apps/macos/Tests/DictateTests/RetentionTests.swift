import XCTest
@testable import Dictate

/// The dashboard retention pass (ROADMAP 0.6) — pure math, engine-free: WPM framed against
/// published typing averages (never a fabricated dictation-population percentile), the
/// corrections-cleaned counter headline, word counts in human units, and the streak heatmap's
/// calendar bucketing (including the DST edge and a non-Gregorian-system-calendar mismatch).
/// Corrections counting itself lives in BasicCleanerTests (it's BasicCleaner's own pure function);
/// the live dashboard states are proven by regression.sh's `--render-home`/`--render-share-card` seams.
final class RetentionTests: XCTestCase {
    // MARK: TypingBaseline — WPM vs published TYPING averages, never a population percentile

    func testMultipleIsNilForZeroWPM() {
        XCTAssertNil(TypingBaseline.multiple(wpm: 0))
        XCTAssertNil(TypingBaseline.headline(wpm: 0))
        XCTAssertNil(TypingBaseline.compactHeadline(wpm: 0))
    }

    func testMultipleAtTheAverageTypistIsOne() {
        XCTAssertEqual(TypingBaseline.multiple(wpm: TypingBaseline.averageTypistWPM), 1.0)
    }

    func testHeadlineNamesTheWPMAndTheMultiple() {
        // 142 / 40 = 3.55 -> one decimal.
        let line = TypingBaseline.headline(wpm: 142)
        XCTAssertEqual(line, "you speak at 142 wpm — ~3.5× the average typist")
    }

    func testCompactHeadlineIsShorterSameNumbers() {
        XCTAssertEqual(TypingBaseline.compactHeadline(wpm: 142), "142 wpm — ~3.5× average")
    }

    func testBelowAverageStillFramesHonestly() {
        // 20 wpm is HALF the average typist — the comparison must flip honestly, never hide below 1×.
        XCTAssertEqual(TypingBaseline.headline(wpm: 20), "you speak at 20 wpm — ~0.5× the average typist")
    }

    // MARK: HumanUnits — word counts translated, never fabricated from zero

    func testHeadlineIsNilForZeroWords() {
        XCTAssertNil(HumanUnits.headline(totalWords: 0, activeDays: 5))
    }

    func testApproxUnderOneShowsLessThanOneNeverZero() {
        XCTAssertEqual(HumanUnits.approx(0.2, unit: "page"), "<1 page")
        XCTAssertEqual(HumanUnits.approx(0.99, unit: "email"), "<1 email")
    }

    func testApproxPluralizesAboveOne() {
        XCTAssertEqual(HumanUnits.approx(1.0, unit: "page"), "~1 page")
        XCTAssertEqual(HumanUnits.approx(2.4, unit: "page"), "~2 pages")
    }

    func testHeadlinePagesAndEmailsPerDay() {
        // 3,500 words / 250 per page = 14 pages. Over 1 active day: 3500/150 = 23.33 -> ~23/day.
        XCTAssertEqual(HumanUnits.headline(totalWords: 3500, activeDays: 1),
                       "~14 pages · ~23 emails a day")
    }

    func testHeadlineDailyRateDividesByActiveDays() {
        // Same 3,500 words spread over 7 days: 3500/150/7 = 3.33 -> ~3/day. Pages don't change (a
        // total, not a rate) — only the per-day email framing divides by the span.
        XCTAssertEqual(HumanUnits.headline(totalWords: 3500, activeDays: 7),
                       "~14 pages · ~3 emails a day")
    }

    func testHeadlineNeverDividesByZeroDays() {
        // activeDays: 0 would be a division by zero — the function must clamp to at least 1 day.
        XCTAssertEqual(HumanUnits.headline(totalWords: 150, activeDays: 0), "<1 page · ~1 email a day")
    }

    // MARK: CorrectionsCleaned — the Home counter, nil at zero, singular/plural

    func testCorrectionsCleanedHeadlineIsNilForZero() {
        XCTAssertNil(CorrectionsCleaned.headline(0))
    }

    func testCorrectionsCleanedHeadlineIsSingularForOne() {
        XCTAssertEqual(CorrectionsCleaned.headline(1), "1 correction cleaned up for you")
    }

    func testCorrectionsCleanedHeadlineIsPluralForMultiple() {
        XCTAssertEqual(CorrectionsCleaned.headline(47), "47 corrections cleaned up for you")
    }

    // MARK: Heatmap — calendar-correct bucketing (empty, single-day, DST)

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func testCellsAreExactlyEightyFourDaysOldestToNewest() {
        let today = utc.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
        let cells = Heatmap.cells(wordsByDay: [:], today: today, calendar: utc)
        XCTAssertEqual(cells.count, Heatmap.days)
        XCTAssertEqual(cells.count, 84)
        XCTAssertEqual(cells.last?.id, "2026-07-11", "the newest cell is today")
        XCTAssertEqual(cells.first?.id, "2026-04-19", "the oldest cell is 83 days before today")
    }

    func testEmptyHistoryIsAllZeroLevel() {
        let today = utc.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
        let cells = Heatmap.cells(wordsByDay: [:], today: today, calendar: utc)
        XCTAssertTrue(cells.allSatisfy { $0.words == 0 && $0.level == 0 },
                     "no history — no divide-by-zero, no fabricated intensity")
    }

    func testSingleDayLightsExactlyOneCellAtMaxIntensity() {
        let today = utc.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
        let cells = Heatmap.cells(wordsByDay: ["2026-07-11": 400], today: today, calendar: utc)
        let lit = cells.filter { $0.words > 0 }
        XCTAssertEqual(lit.count, 1)
        XCTAssertEqual(lit.first?.id, "2026-07-11")
        XCTAssertEqual(lit.first?.level, 4, "the only busy day is, by definition, the busiest day in view")
        XCTAssertTrue(cells.filter { $0.id != "2026-07-11" }.allSatisfy { $0.level == 0 })
    }

    func testLevelBucketsByQuartileOfTheBusiestDay() {
        XCTAssertEqual(Heatmap.level(0, max: 100), 0)
        XCTAssertEqual(Heatmap.level(10, max: 100), 1)
        XCTAssertEqual(Heatmap.level(30, max: 100), 2)
        XCTAssertEqual(Heatmap.level(60, max: 100), 3)
        XCTAssertEqual(Heatmap.level(100, max: 100), 4)
    }

    func testLevelNeverDividesByZero() {
        XCTAssertEqual(Heatmap.level(0, max: 0), 0)
        XCTAssertEqual(Heatmap.level(5, max: 0), 0, "a stray positive count with a zero max still resolves to 0, not a crash")
    }

    /// The DST edge: US Eastern "springs forward" on 2026-03-08 (2:00am -> 3:00am). A calendar
    /// day-walk that used raw 86,400s arithmetic would duplicate or skip a day crossing this
    /// boundary; Calendar.date(byAdding: .day) must not. Injecting a DST-observing timezone
    /// directly (rather than relying on the host machine's zone) makes this deterministic in CI.
    func testCellsStayCalendarCorrectAcrossADSTSpringForward() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let today = ny.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let cells = Heatmap.cells(wordsByDay: [:], today: today, calendar: ny)

        XCTAssertEqual(cells.count, 84, "the DST transition inside the window must not add/drop a day")
        let ids = cells.map { $0.id }
        XCTAssertEqual(Set(ids).count, 84, "every day key must be unique — no duplicated day")
        XCTAssertTrue(ids.contains("2026-03-08"), "the spring-forward day itself must still appear exactly once")
        XCTAssertEqual(cells.last?.id, "2026-03-10")

        // Consecutive cells must be exactly one calendar day apart (never zero, never two) even
        // where the wall-clock offset itself jumps by an hour.
        for i in 1..<cells.count {
            let days = ny.dateComponents([.day], from: cells[i - 1].date, to: cells[i].date).day
            XCTAssertEqual(days, 1, "cells[\(i - 1)] -> cells[\(i)] must be exactly 1 calendar day apart")
        }
    }

    func testDayKeyIsSelfConsistentWithItsOwnCalendar() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let d = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30))!
        XCTAssertEqual(Heatmap.dayKey(d, calendar: ny), "2026-03-08")
    }

    /// `Heatmap.cells`' default calendar must be Gregorian, not `.current` — `InsightStore.
    /// dayFormatter` (the source of every `wordsByDay` key) forces Gregorian via its
    /// `en_US_POSIX` locale no matter what calendar the user picked in System Settings, so a
    /// `.current` default would silently disagree under a Buddhist/Japanese/etc. system calendar
    /// and render the whole grid empty despite real history. This proves the default alone —
    /// with no calendar argument — buckets a store-formatted key correctly, regardless of which
    /// calendar this test happens to run under.
    func testDefaultCalendarMatchesTheStoresGregorianDayKeyRegardlessOfSystemCalendar() {
        let today = Date()
        let key = InsightStore.dayFormatter.string(from: today)
        let cells = Heatmap.cells(wordsByDay: [key: 10], today: today) // no calendar override
        XCTAssertTrue(cells.contains { $0.id == key && $0.words == 10 },
                     "today's store-formatted key must land on a lit cell under the default calendar")
    }

    // MARK: DictationEvent.correctionsCleaned — additive, backward-compatible Codable

    func testCorrectionsCleanedRoundTripsThroughAHistoryLine() throws {
        let e = DictationEvent(id: "r", ts: 5, day: "2026-07-11", text: "ship the myela engine",
                               raw: nil, words: 4, durationMs: 1200, appBundleId: nil, appName: nil,
                               engine: "test", kind: "dictate", status: nil, context: nil,
                               correctionsCleaned: 3)
        let back = try JSONDecoder().decode(DictationEvent.self, from: try JSONEncoder().encode(e))
        XCTAssertEqual(back.correctionsCleaned, 3)
    }

    func testPre061HistoryLinesStillDecodeWithNilCorrectionsCleaned() throws {
        // No `correctionsCleaned` key at all — every history line before this field shipped.
        let legacy = #"{"id":"x","ts":1,"day":"2026-07-11","text":"so the report","words":3,"durationMs":900,"engine":"test","kind":"dictate"}"#
        let e = try JSONDecoder().decode(DictationEvent.self, from: Data(legacy.utf8))
        XCTAssertNil(e.correctionsCleaned)
    }

    func testCorrectionsCleanedTotalTreatsNilAsZero() {
        // InsightStore.correctionsCleanedTotal sums dictations' correctionsCleaned, nil-coalescing
        // to 0 — a mix of measured and pre-existing (nil) events must not crash or skew low/high.
        let values: [Int?] = [3, nil, 2, nil]
        XCTAssertEqual(values.reduce(0) { $0 + ($1 ?? 0) }, 5)
    }

    // MARK: InsightStore.mergedFeed — visible learning (ROADMAP 0.6), pure and singleton-free
    // (InsightStore.shared binds to the real ~/.warble at process init, so its merge logic is
    // pulled out into a static function tests can drive directly with fixtures — no WARBLE_HOME,
    // no touching the real store from `swift test`).

    private func dictationFixture(id: String, ts: Double) -> DictationEvent {
        DictationEvent(id: id, ts: ts, day: "2026-07-11", text: "hello", raw: nil, words: 1,
                       durationMs: 500, appBundleId: nil, appName: nil, engine: "test",
                       kind: "dictate", status: nil, context: nil, correctionsCleaned: nil)
    }

    func testMergedFeedSortsDictationsAndLearnedMomentsByTimeNewestFirst() {
        let events = [dictationFixture(id: "d1", ts: 1), dictationFixture(id: "d2", ts: 3)]
        let learned = [InsightStore.LearnedEvent(id: "l1", ts: 2, word: "Myela", from: "miele")]
        let feed = InsightStore.mergedFeed(events: events, learned: learned, limit: 10)
        XCTAssertEqual(feed.map(\.id), ["d2", "l1", "d1"],
                       "newest (ts=3) first, then the learn moment (ts=2), then the oldest (ts=1)")
    }

    func testMergedFeedRespectsTheLimit() {
        let events = (0..<10).map { dictationFixture(id: "e\($0)", ts: Double($0)) }
        let feed = InsightStore.mergedFeed(events: events, learned: [], limit: 3)
        XCTAssertEqual(feed.map(\.id), ["e9", "e8", "e7"])
    }

    func testMergedFeedWithNothingIsEmpty() {
        XCTAssertTrue(InsightStore.mergedFeed(events: [], learned: [], limit: 8).isEmpty)
    }
}
