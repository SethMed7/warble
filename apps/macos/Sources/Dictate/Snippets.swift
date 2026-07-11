import Foundation

/// Spoken trigger phrase → local text expansion (ROADMAP 0.5): "sign off" becomes your signature,
/// "my address" becomes the address you saved — fully local, managed in the dashboard. Same idiom
/// as the dictionary (see Lexicon.swift): loaded into memory, saved back to disk on every edit, no
/// dependencies. Unlike the dictionary, storage honors WARBLE_HOME (the regression sandbox seam)
/// rather than its own env var — snippets have no reason to live anywhere but ~/.warble.
///
/// Runs AFTER cleanup + the dictionary, BEFORE paste (DictateController.transcribeAndDeliver): a
/// trigger is explicit user intent, never AI rewriting, so it applies at every cleanup level —
/// including None — as long as the user has defined at least one (product.md §4.4/§4.5: verbatim
/// by default, and nothing acts on the user's words uninvited).
final class Snippets {
    static let shared = Snippets()

    private(set) var snippets: [String: String] = [:] // lowercased trigger -> expansion (verbatim, multi-line ok)

    private let comment = "trigger phrases (2+ words recommended) -> the text warble types when you say one, alone or inside a longer dictation. Matched case-insensitively on word boundaries; the longest matching trigger wins. e.g. \"sign off\": \"Best,\\nSeth\"."

    init() { load() }

    /// ~/.warble/snippets.json, or WARBLE_HOME's snippets.json under the regression sandbox — the
    /// same relocation InsightStore/Recovery use, so a check never touches the real file.
    var fileURL: URL {
        let dir: URL
        if let override = ProcessInfo.processInfo.environment["WARBLE_HOME"], !override.isEmpty {
            dir = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".warble")
        }
        return dir.appendingPathComponent("snippets.json")
    }

    func load() {
        snippets = [:]
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let s = obj["snippets"] as? [String: String] {
            for (k, v) in s where !k.isEmpty && !v.isEmpty { snippets[Self.normalizeKey(k)] = v }
        }
    }

    /// Lowercase + collapse internal whitespace to single spaces, so "my  address" (stray double
    /// space) can never coexist as a distinct dict key alongside "my address" — two entries that
    /// would otherwise build the IDENTICAL match pattern (the matcher tolerates any whitespace run
    /// between a trigger's words) but could resolve inconsistently, since a plain `Dictionary`'s
    /// key order isn't stable across runs. Internal (not private) so it's unit-testable directly —
    /// pure, no disk, no environment.
    static func normalizeKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    /// Add a new trigger, or edit an existing one (case-insensitive match on the trigger) — the
    /// dashboard's single Add/Save action. No-op on an empty trigger or expansion.
    func set(trigger: String, expansion: String) {
        let key = Self.normalizeKey(trigger)
        let value = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else { return }
        snippets[key] = value
        save()
    }

    /// Remove one snippet by its trigger (case-insensitive) — the dashboard's delete.
    func forget(_ trigger: String) {
        guard snippets.removeValue(forKey: Self.normalizeKey(trigger)) != nil else { return }
        save()
    }

    /// Apply the loaded snippets to `text` (the already-cleaned, dictionary-applied transcript) —
    /// the instance the real pipeline and the CLI call. Pure matching logic lives in the static
    /// twin below so it's unit-testable with no disk, no environment, and no shared state
    /// (ProcessInfo.environment is snapshotted per process — see HoldCapTests — so a seam that
    /// reads it can't be exercised by toggling env vars mid-test; ResumableFetch.decide is the
    /// same split for the same reason).
    func expand(_ text: String) -> String { Snippets.expand(text, using: snippets) }

    /// The matcher itself: no-op when `snippets` is empty — expansion never fires uninvited. Each
    /// trigger matches case-insensitively on word boundaries, tolerating any run of whitespace
    /// between its words; when a trigger is the whole dictation the whole thing is replaced (no
    /// leftover fragment); inside a longer dictation only its own span is replaced. Overlapping
    /// candidates resolve leftmost-first, and the LONGEST match at a given start wins (so "see you
    /// soon" beats "see you" when both are defined) — ties can't occur, since two distinct
    /// triggers can never match the identical span of text. Matching runs once over the ORIGINAL
    /// text, so an expansion that happens to contain another trigger's words is never re-scanned
    /// (no recursive expansion). `snippets` keys are assumed already-lowercased triggers.
    static func expand(_ text: String, using snippets: [String: String]) -> String {
        guard !snippets.isEmpty else { return text }

        struct Hit { let range: Range<String.Index>; let trigger: String }
        var hits: [Hit] = []
        let whole = NSRange(text.startIndex..., in: text)
        for trigger in snippets.keys {
            let words = trigger.split(whereSeparator: { $0.isWhitespace })
            guard !words.isEmpty else { continue }
            let pattern = "\\b" + words.map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "\\s+") + "\\b"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            re.enumerateMatches(in: text, range: whole) { m, _, _ in
                guard let m, let r = Range(m.range, in: text) else { return }
                hits.append(Hit(range: r, trigger: trigger))
            }
        }
        guard !hits.isEmpty else { return text }

        // Leftmost start wins; the longer of two candidates starting at the same point wins.
        hits.sort { a, b in
            if a.range.lowerBound != b.range.lowerBound { return a.range.lowerBound < b.range.lowerBound }
            return text.distance(from: a.range.lowerBound, to: a.range.upperBound)
                 > text.distance(from: b.range.lowerBound, to: b.range.upperBound)
        }
        var chosen: [Hit] = []
        var frontier = text.startIndex
        for hit in hits where hit.range.lowerBound >= frontier {
            chosen.append(hit)
            frontier = hit.range.upperBound
        }
        guard !chosen.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for hit in chosen {
            result += text[cursor..<hit.range.lowerBound]
            result += snippets[hit.trigger] ?? ""
            cursor = hit.range.upperBound
        }
        result += text[cursor...]
        return result
    }

    private func save() {
        let obj: [String: Any] = ["_comment": comment, "snippets": snippets]
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: fileURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path) // owner-only, like the rest of ~/.warble
    }
}
