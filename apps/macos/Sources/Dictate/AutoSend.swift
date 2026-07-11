import Foundation

/// "Press enter" auto-send (ROADMAP 0.5): say "press enter" or "press return" at the very END of a
/// dictation and, once you've turned it on, warble sends a Return keystroke right after the paste
/// lands — huge for chat apps. OFF by default (product.md §4.5: nothing acts on your words without
/// being asked, and once off it never re-enables itself); the toggle lives in the Dictate menu.
///
/// SAFETY the caller (DictateController.deliver) is responsible for: the Return keystroke fires
/// ONLY after a successful paste, and NEVER when a secure (password) field was focused at
/// recording start — that's `dictationSecure`/`ctx.secure`, the same signal InsightStore already
/// uses to keep secure-field dictations to metrics-only (see InsightStore.record). AutoSend itself
/// stays pure text-in/text-out so it's unit-testable with no AX, no events, no environment.
enum AutoSend {
    /// Persisted in UserDefaults, like DictateSounds.enabled — off by default, one click to turn
    /// on, and never flips itself back (product.md §4.5).
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "autoSendEnabled") } // absent -> false, i.e. off
        set { UserDefaults.standard.set(newValue, forKey: "autoSendEnabled") }
    }

    /// The toggle-aware entry point the real pipeline and the CLI both call, run on the fully
    /// cleaned text (cleanup -> dictionary -> snippets, in that order — same leg order
    /// DictateController.transcribeAndDeliver already documents; AutoSend is the final leg).
    /// `said` names which phrase fired ("press enter" / "press return"), for the pill's landed
    /// copy — empty when `send` is false.
    ///
    /// OFF: always verbatim, `send: false` — even when the dictation ends with the phrase, so a
    /// user who hasn't opted in sees no hint, no strip, no surprise (product.md §4.5/§4.6).
    /// ON: strips the phrase only when it's in the FINAL position and reports `send: true`;
    /// anywhere else in the text it's left completely alone (someone dictating instructions must
    /// still be able to say the words).
    static func apply(_ text: String) -> (send: Bool, pasted: String, said: String) {
        guard enabled else { return (false, text, "") }
        let hit = detectFinal(text)
        return hit.matched ? (true, hit.stripped, hit.said) : (false, text, "")
    }

    /// Pure detector: is the text's LAST spoken word-pair "press enter" / "press return" (any
    /// case, any trailing punctuation)? Token-based rather than a whole-string regex so internal
    /// newlines from a spoken "new line" survive untouched in `stripped` — only the trailing
    /// command tokens (and the whitespace that separated them from the rest) are dropped. Splits
    /// into `Substring`s (not `String`s) so each token keeps its real index into `text` — the
    /// second-to-last token's own `startIndex` is exactly where the command begins, no re-search
    /// needed (and so no risk of matching an earlier, coincidental occurrence of the same word).
    static func detectFinal(_ text: String) -> (matched: Bool, stripped: String, said: String) {
        let toks = text.split(whereSeparator: { $0.isWhitespace })
        guard toks.count >= 2 else { return (false, text, "") }
        let secondLastTok = toks[toks.count - 2]
        let lastTok = toks[toks.count - 1]
        let last = core(String(lastTok)).lowercased()
        let secondLast = core(String(secondLastTok)).lowercased()
        guard secondLast == "press", last == "enter" || last == "return" else { return (false, text, "") }

        var stripped = String(text[text.startIndex..<secondLastTok.startIndex])
        // Trim only the whitespace that separated the command from the rest — never touch
        // whitespace/newlines earlier in the dictation.
        while let l = stripped.last, l.isWhitespace { stripped.removeLast() }
        return (true, stripped, "press \(last)")
    }

    /// Token stripped of leading/trailing non-alphanumerics ("enter." -> "enter", "PRESS" ->
    /// "PRESS") — the same idiom SpellOut.core uses, so trailing punctuation is tolerated without
    /// a regex.
    private static func core(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}
