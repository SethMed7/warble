import Foundation

/// Swift twin of core/clean.ts (the canonical, acceptance-tested cleaner). The app runs this port
/// directly — the rules ship with the binary, so a stale deployed helper can never shadow them.
/// Keep the pass order and rules identical in both files.
enum BasicCleaner {

    static func cleaned(_ s: String, category: AppCategory? = nil) -> String {
        // NFC first: Swift's == is canonical-equivalent, JS's === is code-unit — without a shared
        // normal form, mixed NFC/NFD duplicates would collapse in one twin and not the other.
        let trimmed = s.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let startedUpper = trimmed.first?.isUppercase == true
        var tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        tokens = applyScratchThat(tokens)
        // Fillers go before corrections so "2 um actually 3" still corrects to "3".
        tokens = removeFillers(tokens)
        tokens = applyCorrections(tokens)
        tokens = collapseDuplicates(tokens)
        // (e) tidy: whitespace collapse comes free from the token join.
        var out = tokens.joined(separator: " ")
            .replacingOccurrences(of: "\\s+([.,!?;:])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // Acceptance outputs stay lowercase: only capitalize when the raw text did.
        if startedUpper, let first = out.first {
            out = String(first).uppercased() + String(out.dropFirst())
        }
        // (f) category tone — additive, gated on category (see below).
        switch category {
        case .editor: out = stripShortTrailingPeriod(out, maxWords: shortCommandWords)
        case .chat:   out = stripShortTrailingPeriod(out, maxWords: shortMessageWords)
        default:      break
        }
        return out
    }

    /// Corrections cleaned (ROADMAP 0.6 dashboard — "corrections cleaned for you"): how many
    /// filler words, false-start corrections ("no wait", "actually", "scratch that"), and
    /// duplicate-word collapses the deterministic pass removes from `raw` — the token-count
    /// difference between the input and the SAME (a)-(d) stages `cleaned(_:)` runs, stopping
    /// short of (f): category tone (the trailing-period rule) is a style choice, not a
    /// correction, so it never counts. Pure and cheap; called once per dictation at clean time
    /// (DictateController) so the count can be stored on the event — it can't be recovered later
    /// from the already-cleaned text, only from the raw ASR output.
    static func correctionsCount(_ s: String) -> Int {
        let trimmed = s.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var out = tokens
        out = applyScratchThat(out)
        out = removeFillers(out)
        out = applyCorrections(out)
        out = collapseDuplicates(out)
        return max(0, tokens.count - out.count)
    }

    // MARK: - Vocabulary

    /// Non-lexical hesitations only — anything that can carry meaning (huh, like,
    /// well, right) belongs to the LLM pass. "mm" stays out: it reads as
    /// millimetres ("a 3 mm gap").
    private static let fillers: Set<String> = [
        "um", "umm", "uhm", "uh", "uhh", "er", "erm", "ah", "hmm", "hmmm", "mmm", "mhm", "mhmm",
    ]

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
        "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million",
    ]

    /// Longest match first: two-word markers before single-word ones.
    private static let markers: [[String]] = [
        ["no", "wait"], ["wait", "no"], ["i", "mean"], ["make", "that"],
        ["actually"], ["rather"],
    ]

    // MARK: - Token helpers

    /// Token without leading/trailing punctuation (keeps inner apostrophes).
    private static func core(_ token: String) -> String {
        let keep = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        return token.trimmingCharacters(in: keep.inverted)
    }

    private enum Shape { case numeral, numberWord, capitalized, plain }

    private static func shape(_ token: String) -> Shape {
        let c = core(token)
        if !c.isEmpty, c.allSatisfy({ $0.isASCII && $0.isNumber }) { return .numeral }
        if numberWords.contains(c.lowercased()) { return .numberWord }
        if c.first?.isUppercase == true { return .capitalized }
        return .plain
    }

    private static func endsSentence(_ token: String) -> Bool {
        guard let last = token.last else { return false }
        return ".!?".contains(last)
    }

    private static func endsClause(_ token: String) -> Bool {
        guard let last = token.last else { return false }
        return ".,!?;:".contains(last)
    }

    // MARK: - Passes (same order as clean.ts)

    /// (a) "scratch that" drops everything back to the last sentence boundary.
    private static func applyScratchThat(_ tokens: [String]) -> [String] {
        var out = tokens
        var i = 0
        while i + 1 < out.count {
            if core(out[i]).lowercased() == "scratch", core(out[i + 1]).lowercased() == "that" {
                var start = 0
                var j = i - 1
                while j >= 0 {
                    if endsSentence(out[j]) {
                        start = j + 1
                        break
                    }
                    j -= 1
                }
                out.removeSubrange(start..<(i + 2))
                i = start
            } else {
                i += 1
            }
        }
        return out
    }

    private static func markerMatch(_ tokens: [String], at i: Int) -> [String]? {
        for words in markers {
            var matched = true
            for (k, w) in words.enumerated() {
                if i + k >= tokens.count || core(tokens[i + k]).lowercased() != w {
                    matched = false
                    break
                }
            }
            if matched { return words }
        }
        return nil
    }

    /// (b) "<A> <marker> <B>": when A and B share a shape, keep B, drop A + marker.
    private static func applyCorrections(_ tokens: [String]) -> [String] {
        var out = tokens
        var i = 1 // a correction needs a token A before the marker
        while i < out.count {
            if let marker = markerMatch(out, at: i) {
                let bIndex = i + marker.count
                if bIndex < out.count, shape(out[i - 1]) == shape(out[bIndex]) {
                    out.removeSubrange((i - 1)..<(i + marker.count))
                    i = max(1, i - 1)
                    continue
                }
            }
            i += 1 // unmatched markers stay
        }
        return out
    }

    /// (c) Standalone fillers, plus "you know" as a bare interjection.
    private static func removeFillers(_ tokens: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            let c = core(tokens[i]).lowercased()
            if fillers.contains(c) {
                i += 1
                continue
            }
            if c == "you", i + 1 < tokens.count, core(tokens[i + 1]).lowercased() == "know" {
                // Bare = set off by punctuation or dangling at the end
                // ("you know the answer" must survive).
                let afterPunct = out.last.map(endsClause) == true
                if endsClause(tokens[i + 1]) || i + 2 == tokens.count || afterPunct {
                    i += 2
                    continue
                }
            }
            out.append(tokens[i])
            i += 1
        }
        return out
    }

    /// (d) Collapse immediate duplicate words ("like like" -> "like"); never
    /// across a sentence boundary ("stop. Stop" stays). Deliberately NO
    /// two-word version: X-C-X idioms ("again and again", "day by day"), spoken
    /// digit runs ("zero four zero four"), and coordinations ("tried again and
    /// again and failed") make any pair collapse meaning-destroying — two-word
    /// false starts belong to the guarded LLM pass.
    private static func collapseDuplicates(_ tokens: [String]) -> [String] {
        var out: [String] = []
        for token in tokens {
            if let prev = out.last, !endsSentence(prev), !core(prev).isEmpty,
               core(prev).lowercased() == core(token).lowercased() {
                // Keep the first copy, unless the later one carries punctuation.
                if endsClause(token) { out[out.count - 1] = token }
            } else {
                out.append(token)
            }
        }
        return out
    }

    /// (f) Category tone (ROADMAP 0.6 — the apply half of local-only context awareness). When the
    /// caller knows where the dictation is headed (the locally derived app category — captured
    /// only when the user opted in), the output is shaped by small additive rules gated on that
    /// category; no category means the pre-0.6 output, byte for byte. The one deterministic
    /// transform: editors/terminals and chat apps drop the ASR's trailing period on a short
    /// one-liner (a period is an artifact on "git status" and reads stiff in chat); mail and
    /// documents keep today's full punctuation. Casing and contractions are never touched
    /// anywhere — the words stay the user's (product.md §4.4).
    private static let shortCommandWords = 6 // editor/terminal: commands are terse
    private static let shortMessageWords = 12 // chat: messages run a little longer

    private static func stripShortTrailingPeriod(_ text: String, maxWords: Int) -> String {
        guard text.hasSuffix("."), !text.hasSuffix("..") else { return text } // one plain final period only
        // A sentence boundary inside means prose — keep the period. Technical dots ("main.py",
        // "v2.0") are not followed by whitespace, so they don't count.
        guard text.range(of: "[.!?]\\s", options: .regularExpression) == nil else { return text }
        let body = String(text.dropLast())
        guard body.split(whereSeparator: { $0.isWhitespace }).count <= maxWords else { return text }
        return body
    }
}
