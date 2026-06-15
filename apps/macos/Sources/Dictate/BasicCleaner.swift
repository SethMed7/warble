import Foundation

/// Swift twin of scripts/clean.ts (the canonical cleaner). The app prefers the
/// bun helper in ~/.dictado when installed; this port keeps dictado working
/// with zero setup. Keep the pass order and rules identical in both files.
enum BasicCleaner {

    static func cleaned(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return out
    }

    // MARK: - Vocabulary

    private static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "mhm",
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
    /// across a sentence boundary ("stop. Stop" stays).
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
}
