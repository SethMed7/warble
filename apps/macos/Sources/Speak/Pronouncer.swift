import Foundation

/// Read-aloud pronunciations, sourced from the shared voz dictionary (~/.voz/dictionary.json).
/// Dictation's Lexicon writes them — a canonical word → a "say it like" respelling (e.g.
/// "myela" → "my-ell-uh") — and read-aloud applies them to the text just before it's spoken,
/// so a word voz learned to spell is also *said* the way you mean.
///
/// This shares the FILE with the dictation Lexicon, not code: the two capabilities stay
/// separate modules (Speak never imports Dictate), exactly like they share core/ as files.
final class Pronouncer {
    static let shared = Pronouncer()

    private var map: [String: String] = [:]   // lowercased word -> respelling
    private var loadedFrom: URL?
    private var loadedAt: Date?

    /// Same resolution as the dictation Lexicon: VOZ_DICTIONARY/DICTADO_DICTIONARY env, the saved
    /// location, then ~/.voz (or an existing ~/.dictado). Kept in lockstep with Lexicon.fileURL.
    private var fileURL: URL {
        for key in ["VOZ_DICTIONARY", "DICTADO_DICTIONARY"] {
            if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
                return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
            }
        }
        if let saved = UserDefaults.standard.string(forKey: "dictionaryPath"), !saved.isEmpty {
            return URL(fileURLWithPath: saved)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let voz = home.appendingPathComponent(".voz/dictionary.json")
        let legacy = home.appendingPathComponent(".dictado/dictionary.json")
        if FileManager.default.fileExists(atPath: voz.path) { return voz }
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return voz
    }

    /// Reload only when the file path or its modification date changed — cheap to call before a read,
    /// so edits made in the dashboard take effect on the next selection without a restart.
    private func reloadIfNeeded() {
        let url = fileURL
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mod = attrs?[.modificationDate] as? Date
        if url == loadedFrom, mod == loadedAt { return }
        loadedFrom = url; loadedAt = mod
        map = [:]
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = obj["pronunciations"] as? [String: String] else { return }
        for (k, v) in p where !k.isEmpty && !v.isEmpty { map[k.lowercased()] = v }
    }

    /// Replace whole-word occurrences of any known word with its respelling (case-insensitive).
    /// Returns the text unchanged when there are no pronunciations.
    func apply(_ text: String) -> String {
        reloadIfNeeded()
        guard !map.isEmpty else { return text }
        var result = text
        for (word, say) in map {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range,
                                                 withTemplate: NSRegularExpression.escapedTemplate(for: say))
        }
        return result
    }
}
