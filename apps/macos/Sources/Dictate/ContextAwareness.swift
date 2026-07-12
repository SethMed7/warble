import ApplicationServices
import Foundation

/// Local-only context awareness (ROADMAP 0.6) — the capture half. When the user has switched it
/// on (OFF by default, and it never re-enables itself — product.md §4.5), warble reads a bounded
/// sliver of context at dictation start: the frontmost app's identity (already captured for
/// per-app stats), a category derived locally from a small static bundle-id map, and at most
/// ~200 words of text near the cursor via the same focused-field Accessibility read
/// learn-from-edits (CorrectionListener) already uses — never screenshots, never other windows or
/// apps, and never anything in a secure (password) context: when a secure field is focused,
/// nothing is captured at all, not even the app. The gates run BEFORE any AX read, so off or
/// secure means zero reads, not zero retention.
///
/// Lifecycle (product.md §4.8 — local data is also a privacy surface): the captured text lives in
/// memory for the one dictation (CapturedContext, deliberately NOT Codable), and only a compact
/// note of what was read — app, category, word count, a ≤12-word (≤120-char) preview — persists on the
/// DictationEvent (ContextRecord, whose only initializer derives that preview, so no field can
/// hold the full text). Precision (product.md §4.9): captured context is never handed to any
/// network-capable code path — its only consumers are DictateController → the in-memory
/// DictationContext → InsightStore's bounded ContextRecord — and this module's only network I/O
/// is the loopback link to warble's own local engines (WarmASR/WarmLLM via Shared/LoopbackHTTP).
enum ContextAwareness {
    /// The dashboard toggle (Data & Privacy ▸ Context awareness). Absent → OFF: capture is
    /// opt-in, and once off it stays off — nothing ever flips it back (product.md §4.5).
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "contextAwareness") } // absent -> false, i.e. off
        set { UserDefaults.standard.set(newValue, forKey: "contextAwareness") }
    }

    /// The word cap: at most this many words of text near the cursor are ever read.
    static let maxWords = 200

    /// The pure gate + bounds, unit-tested and driven headlessly by --context-sim (a fixture
    /// stands in for the AX-read text). Off → nil (off-zero). Secure → nil (secure-zero: nothing
    /// is captured at all). Otherwise the text is clipped to its LAST `maxWords` words — the end
    /// of a field's value is what sits nearest the cursor while composing.
    static func capture(enabled: Bool, secure: Bool, bundleId: String?, name: String?,
                        text: String?, focusedRole: String?) -> CapturedContext? {
        guard enabled, !secure else { return nil }
        return CapturedContext(appBundleId: bundleId, appName: name,
                               category: categorize(bundleId: bundleId, focusedRole: focusedRole),
                               text: text.map { clip($0) } ?? "")
    }

    /// The live path DictateController calls at recording start. The gates come BEFORE any AX
    /// read — with the toggle off or a secure field focused, the focused element is never even
    /// looked at. The AX read itself is CorrectionListener's exact focused-field read (widened to
    /// internal for reuse), so this adds no new Accessibility surface: apps that expose nothing
    /// readable degrade to an app-identity-only capture (words: 0).
    static func captureLive(secure: Bool, bundleId: String?, name: String?) -> CapturedContext? {
        guard enabled, !secure else { return nil }
        var text: String?
        var role: String?
        if AXIsProcessTrusted(), let el = CorrectionListener.focusedElement() {
            role = CorrectionListener.stringAttr(el, kAXRoleAttribute)
            text = CorrectionListener.value(of: el)
        }
        return capture(enabled: true, secure: false, bundleId: bundleId, name: name,
                       text: text, focusedRole: role)
    }

    /// Clip to the LAST `maxWords` words — the end of the value is nearest the cursor.
    static func clip(_ text: String, maxWords: Int = ContextAwareness.maxWords) -> String {
        let toks = text.split(whereSeparator: { $0.isWhitespace })
        guard toks.count > maxWords else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return toks.suffix(maxWords).joined(separator: " ")
    }

    // MARK: category — derived locally, a small static map + a keyword fallback

    /// A handful of apps everyone has, by exact bundle id. Deliberately small: the keyword
    /// fallback below catches families (any "…mail…" app), and everything else is `other` —
    /// ambiguity resolves toward claiming LESS about where the user is.
    private static let bundleCategories: [String: AppCategory] = [
        // mail
        "com.apple.mail": .mail,
        "com.microsoft.Outlook": .mail,
        "com.readdle.smartemail-Mac": .mail,
        // chat
        "com.apple.MobileSMS": .chat,
        "com.tinyspeck.slackmacgap": .chat,
        "com.hnc.Discord": .chat,
        "ru.keepcoder.Telegram": .chat,
        "net.whatsapp.WhatsApp": .chat,
        "com.microsoft.teams2": .chat,
        // editor / terminal
        "com.apple.dt.Xcode": .editor,
        "com.microsoft.VSCode": .editor,
        "com.apple.Terminal": .editor,
        "com.googlecode.iterm2": .editor,
        "com.mitchellh.ghostty": .editor,
        "dev.zed.Zed": .editor,
        "com.sublimetext.4": .editor,
        // document
        "com.apple.Notes": .document,
        "com.apple.TextEdit": .document,
        "com.apple.iWork.Pages": .document,
        "com.microsoft.Word": .document,
    ]

    /// Keyword fallback over the lowercased bundle id, first hit wins.
    private static let keywordCategories: [(keyword: String, category: AppCategory)] = [
        ("mail", .mail),
        ("slack", .chat), ("discord", .chat), ("telegram", .chat), ("whatsapp", .chat),
        ("messages", .chat), ("chat", .chat), ("signal", .chat),
        ("term", .editor), ("code", .editor), ("vim", .editor), ("emacs", .editor),
        ("jetbrains", .editor), ("editor", .editor),
        ("word", .document), ("pages", .document), ("notes", .document), ("docs", .document),
        ("write", .document), ("text", .document),
    ]

    /// Static map → keyword fallback → one nudge: an app we can't otherwise place whose focused
    /// element is a multi-line AXTextArea is being written in like a document. That's the whole
    /// heuristic — no window titles, no content sniffing.
    static func categorize(bundleId: String?, focusedRole: String? = nil) -> AppCategory {
        let category = baseCategory(bundleId: bundleId)
        if category == .other, focusedRole == (kAXTextAreaRole as String) { return .document }
        return category
    }

    private static func baseCategory(bundleId: String?) -> AppCategory {
        guard let id = bundleId, !id.isEmpty else { return .other }
        if let hit = bundleCategories[id] { return hit }
        let lower = id.lowercased()
        for (keyword, category) in keywordCategories where lower.contains(keyword) { return category }
        return .other
    }
}

/// Where a dictation is being aimed, described no finer than warble needs for tone.
enum AppCategory: String {
    case mail, chat, editor, document, other
}

/// The captured sliver, in memory for exactly one dictation. Deliberately NOT Codable — the full
/// text has no encodable form anywhere in the app, so it structurally cannot be persisted; what
/// history keeps is the bounded ContextRecord derived from it.
struct CapturedContext {
    let appBundleId: String?
    let appName: String?
    let category: AppCategory
    let text: String   // already clipped to ≤ ContextAwareness.maxWords words; "" when unreadable
}

/// The session-scoped holder for the captured sliver (a ROADMAP 0.7 precision follow-up): the
/// capture must never outlive its dictation. `begin` at recording start, `take` exactly once on
/// the deliver path, `abort` on EVERY abort path (mic error, no clip, too short, silent, Esc,
/// mode off). Take-once is structural — `take` empties the holder, so nothing can read the sliver
/// twice — and the post-abort state is unit-tested (ContextAwarenessTests). DictateController
/// owns the live wiring; regression.sh's `transparency` check counts the abort calls.
struct SessionCapture {
    private var captured: CapturedContext?

    /// A new dictation session started — whatever a previous session left behind is replaced.
    mutating func begin(_ c: CapturedContext?) { captured = c }

    /// The deliver path's one read: hands the capture over and empties the holder.
    mutating func take() -> CapturedContext? {
        defer { captured = nil }
        return captured
    }

    /// The session ended without delivering — drop the capture on the spot.
    mutating func abort() { captured = nil }

    /// Test seam only: is anything held right now? (The post-abort assertion.)
    var isHolding: Bool { captured != nil }
}

/// The compact, inspectable note of what context awareness read for one dictation — app,
/// category, word count, and a ≤12-word, ≤120-character preview. Its ONLY initializer derives
/// the preview from a CapturedContext, so no field can ever hold the full text: the caps are
/// structural, not behavioral (the 13th word is unencodable by construction, and a
/// whitespace-free run — a token the word cap alone couldn't bound — is cut at the character
/// cap; both asserted in ContextAwarenessTests).
struct ContextRecord: Codable, Hashable {
    let app: String        // the app's name (falling back to bundle id) — what the user recognizes
    let category: String   // AppCategory.rawValue: mail | chat | editor | document | other
    let words: Int         // how many words were read (≤ ContextAwareness.maxWords)
    let preview: String    // the first ≤12 words (≤120 chars) of what was read, "…"-terminated when clipped

    static let previewWords = 12
    static let previewMaxChars = 120 // so a single huge token (a URL, minified code) can't balloon the note

    init(_ captured: CapturedContext) {
        app = captured.appName ?? captured.appBundleId ?? "unknown"
        category = captured.category.rawValue
        let toks = captured.text.split(whereSeparator: { $0.isWhitespace })
        words = toks.count
        var p = toks.prefix(Self.previewWords).joined(separator: " ")
        var clipped = toks.count > Self.previewWords
        if p.count > Self.previewMaxChars {
            p = String(p.prefix(Self.previewMaxChars))
            clipped = true
        }
        preview = clipped ? p + "…" : p
    }

    /// The inspect half (ROADMAP 0.6): the quiet one-line disclosure History shows for any
    /// dictation that captured context — "context: Mail (mail) · 42 words read · “Re: the Q3
    /// numbers…”". Pure and unit-tested (ContextAwarenessTests): the preview is already bounded to
    /// ≤12 words by the only initializer above, so this never un-caps it, it only formats what's
    /// already there. An app-identity-only capture (words: 0, an unreadable field) drops the
    /// quoted clause instead of showing empty quotes — the missing-field case.
    var displayLine: String {
        let read = "\(words) word\(words == 1 ? "" : "s") read"
        let base = "context: \(app) (\(category)) · \(read)"
        return preview.isEmpty ? base : "\(base) · “\(preview)”"
    }
}
