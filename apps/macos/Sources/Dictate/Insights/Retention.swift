import Foundation

/// The dashboard retention pass (ROADMAP 0.6) — pure, locally computed math with no dependency on
/// InsightStore, so every edge (zero history, a single day, a DST boundary) is unit-testable
/// without touching the real store. Every number here is derived from stats already on disk;
/// nothing is measured against another warble user, because there is no population to measure
/// against (product.md §4.9 — precision in every public claim, never fabricate one).
enum TypingBaseline {
    /// Widely cited average adult typing speed (various typing-test aggregators, e.g. Ratatype/
    /// typing.com class-of-thousands averages cluster around 38-42 WPM) — 40 is the round middle.
    static let averageTypistWPM = 40
    /// Widely cited professional/touch-typist speed (the same sources put trained typists in the
    /// 65-75 WPM band) — kept here as the cited upper reference, not used in the headline copy.
    static let proTypistWPM = 75

    /// The multiple over an average typist, one decimal — nil for 0 WPM (nothing dictated yet, so
    /// nothing to compare).
    static func multiple(wpm: Int) -> Double? {
        guard wpm > 0 else { return nil }
        return Double(wpm) / Double(averageTypistWPM)
    }

    /// Home's full sentence: "you speak at 142 wpm — ~3.5× the average typist." Never a dictation-
    /// population percentile — warble has no population to compare against.
    static func headline(wpm: Int) -> String? {
        guard let m = multiple(wpm: wpm) else { return nil }
        return "you speak at \(wpm) wpm — ~\(oneDecimal(m))× the average typist"
    }

    /// The share card's compact form — same numbers, shorter copy: "142 wpm — ~3.5× average".
    static func compactHeadline(wpm: Int) -> String? {
        guard let m = multiple(wpm: wpm) else { return nil }
        return "\(wpm) wpm — ~\(oneDecimal(m))× average"
    }

    private static func oneDecimal(_ d: Double) -> String { String(format: "%.1f", d) }
}

/// Word counts translated into everyday things, so "48,213 words" reads as something felt rather
/// than an abstract count. The constants are widely used rough approximations, not measurements —
/// documented here so a future change is deliberate, never presented as a precise fact.
enum HumanUnits {
    /// The standard manuscript-page convention (double-spaced, 12pt) publishing and word
    /// processors use for page-count estimates.
    static let wordsPerPage = 250
    /// The rough middle of commonly cited average business-email lengths (e.g. Boomerang's
    /// oft-quoted email-length study and similar) — used only for a light, clearly-approximate
    /// "~N emails a day" framing.
    static let wordsPerEmail = 150

    /// "~14 pages · ~2 emails a day" — nil when nothing's been dictated yet (no fabricated stat
    /// from zero). `activeDays` should be the calendar span since the first dictation (at least
    /// 1) — see InsightStore.daysSinceFirstDictation — so the daily rate isn't inflated by
    /// counting only days you happened to use warble.
    static func headline(totalWords: Int, activeDays: Int) -> String? {
        guard totalWords > 0 else { return nil }
        let pages = Double(totalWords) / Double(wordsPerPage)
        let perDay = Double(totalWords) / Double(wordsPerEmail) / Double(max(1, activeDays))
        return "\(approx(pages, unit: "page")) · \(approx(perDay, unit: "email")) a day"
    }

    /// "~14 pages", "<1 page" — never "~0 pages": a value under 1 says so plainly instead of
    /// rounding down to a number that reads like nothing happened.
    static func approx(_ value: Double, unit: String) -> String {
        guard value >= 1 else { return "<1 \(unit)" }
        let n = Int(value.rounded())
        return "~\(n) \(unit)\(n == 1 ? "" : "s")"
    }
}

/// Corrections cleaned (ROADMAP 0.6 dashboard): a plain counter for the filler/false-start/
/// duplicate removals `BasicCleaner.correctionsCount` tallied across every dictation
/// (`InsightStore.correctionsCleanedTotal` sums them) — surfaced on Home so the number isn't just
/// stored invisibly. Nil at zero: a brand-new install (or one with only pre-0.6.1 history, which
/// has no count at all) shows nothing rather than a hollow "0 corrections cleaned."
enum CorrectionsCleaned {
    static func headline(_ total: Int) -> String? {
        guard total > 0 else { return nil }
        return "\(total) correction\(total == 1 ? "" : "s") cleaned up for you"
    }
}

/// The streak heatmap's pure bucketing (ROADMAP 0.6 — GitHub-style day grid, last ~12 weeks).
/// Calendar-correct by construction: every step walks `Calendar.date(byAdding:)`, never raw
/// 86,400-second arithmetic, so a DST transition inside the window can't duplicate or skip a day
/// (the same discipline InsightStore.dayStreak already uses). Pure and dependency-injected
/// (calendar + "today" are parameters) so DST/empty/single-day edges are unit-testable without
/// touching the real store or the host machine's timezone.
enum Heatmap {
    static let weeks = 12
    static let days = weeks * 7 // 84, including today

    struct Cell: Identifiable, Equatable {
        let id: String   // the calendar-day key, e.g. "2026-07-11"
        let date: Date
        let words: Int
        let level: Int    // 0...4 — the tint-ramp bucket (0 = nothing dictated that day)
    }

    /// `wordsByDay` keys must be the SAME calendar-day key `calendar` would derive for each date.
    /// The default is an explicit Gregorian calendar, NOT `.current`: `InsightStore.dayFormatter`
    /// forces Gregorian via its `en_US_POSIX` locale regardless of what calendar the user has
    /// picked in System Settings, so `.current` would silently disagree (and render an all-empty
    /// grid despite real data) under a Buddhist/Japanese/etc. system calendar. Both still default
    /// to the local time zone (`TimeZone.current`), so the day boundary itself is unchanged.
    /// Oldest to newest, always exactly `days` long.
    static func cells(wordsByDay: [String: Int], today: Date = Date(),
                      calendar: Calendar = Calendar(identifier: .gregorian)) -> [Cell] {
        let start = calendar.startOfDay(for: today)
        let maxWords = wordsByDay.values.max() ?? 0
        return (0..<days).reversed().compactMap { offset -> Cell? in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let key = dayKey(d, calendar: calendar)
            let words = wordsByDay[key] ?? 0
            return Cell(id: key, date: d, words: words, level: level(words, max: maxWords))
        }
    }

    /// A zero-padded "yyyy-MM-dd" derived straight from `calendar`'s own components — self-
    /// consistent with whatever calendar/timezone `cells` was called with (never a separate
    /// DateFormatter whose timezone could silently disagree with the injected calendar).
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 5-level intensity (0 = nothing, 1...4 = quartiles of the busiest day in view). An all-zero
    /// history (or a single busy day, `max == words`) still resolves cleanly: `max == 0` forces
    /// every cell to level 0 rather than dividing by zero.
    static func level(_ words: Int, max: Int) -> Int {
        guard words > 0, max > 0 else { return 0 }
        let ratio = Double(words) / Double(max)
        if ratio > 0.75 { return 4 }
        if ratio > 0.5  { return 3 }
        if ratio > 0.25 { return 2 }
        return 1
    }
}
