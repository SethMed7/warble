import Foundation

/// The optional, on-device "Insights AI" layer: a weekly summary, suggested dictionary words, and
/// nudges, all derived from the LOCAL stats `InsightStore` already keeps. Behind a default-off master
/// switch (`InsightStore.aiInsightsEnabled`), cached to ~/.warble/insights-ai.json, and graceful when the
/// model isn't installed. 100% on-device — the same warm MLX server that polishes dictation, never the
/// network.
///
/// The split, by design: **suggestions** and **nudges** are computed DETERMINISTICALLY (from
/// `Lexicon.pending` and `InsightStore` aggregates — they work with no model, even in stats-only mode).
/// The **summary** is the one generative piece, and it phrases AGGREGATE NUMBERS only (never the raw
/// transcript log) via `WarmLLM.generate`, falling back to a deterministic template on any failure so a
/// card is never broken or empty.

/// One suggested dictionary rule ("you keep fixing devil → Dhaval — make it a rule?"). `id` is the
/// `to` target's lowercase key (stable across regenerations, so Accept/Dismiss survive a refresh).
struct AISuggestion: Codable, Identifiable, Hashable {
    let id: String
    let from: String     // a representative mis-hearing the recognizer produced
    let to: String       // the spelling/casing you actually want
    let reason: String   // warm, factual: "You've corrected this 3× — make it a rule?"
}

/// The cached AI output for one data window. `windowHash` is a cheap fingerprint of the underlying
/// stats; when it changes (or the snapshot ages past 7 days) the auto path regenerates.
struct AISnapshot: Codable {
    let generatedAt: Double          // Unix epoch seconds, UTC — when this snapshot was produced
    let windowHash: String           // fingerprint of the data window it summarizes
    let summary: String              // 2–3 warm, factual sentences over the week
    let nudges: [String]             // 1–3 short computed insights
    let suggestions: [AISuggestion]  // deterministic suggested-word rules, Accept/Dismiss
}

/// Owns the AI snapshot: loads/saves the cache, gates everything on the master switch + model
/// availability, and produces a new snapshot off the main thread. Created by the UI (no singleton);
/// reads `InsightStore.shared` / `Lexicon.shared` for the data it summarizes.
final class AIInsightsStore: ObservableObject {
    @Published private(set) var snapshot: AISnapshot?
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?

    private let fileURL: URL    // ~/.warble/insights-ai.json
    private let queue = DispatchQueue(label: "warble.insights.ai", qos: .utility)
    private var clearObserver: NSObjectProtocol?   // wipes the cache when the user clears their history

    /// The on-device engine gate: no model installed → the whole feature is dark (cards hidden).
    var isAvailable: Bool { WarmLLM.isInstalled() }

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".warble")
        fileURL = dir.appendingPathComponent("insights-ai.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        load()
        // When the user clears their history (InsightStore.clearAll), wipe the AI cache in lockstep —
        // both the in-memory snapshot and, via save(), the on-disk ~/.warble/insights-ai.json.
        clearObserver = NotificationCenter.default.addObserver(
            forName: .warbleInsightsCleared, object: nil, queue: .main) { [weak self] _ in
            self?.snapshot = nil
            self?.save()
        }
    }

    deinit { if let o = clearObserver { NotificationCenter.default.removeObserver(o) } }

    // MARK: generation

    /// The AUTO path: regenerate only when worthwhile. No-op unless the master switch + auto-refresh are
    /// on and the model is installed; then regenerate only if the cache is empty, older than 7 days, or
    /// its `windowHash` no longer matches the current data window. Off the main thread; publishes on it.
    func refreshIfNeeded() {
        guard InsightStore.shared.aiInsightsEnabled,
              InsightStore.shared.aiInsightsAutoRefresh,
              isAvailable else { return }
        let hash = Self.windowHash()
        if let s = snapshot,
           s.windowHash == hash,
           Date().timeIntervalSince1970 - s.generatedAt < 7 * 24 * 3600 { return } // fresh enough
        generate(force: false)
    }

    /// The ON-DEMAND path: force a regeneration regardless of cache freshness (the "Regenerate" button).
    /// Guarded by the master switch + model availability; off the main thread.
    func regenerate() {
        guard InsightStore.shared.aiInsightsEnabled, isAvailable else { return }
        generate(force: true)
    }

    /// Kick off a generation pass. MUST be called on the main thread: it captures everything it needs
    /// from `InsightStore`/`Lexicon` HERE, on main, so the background pass touches NO shared mutable
    /// state. Those stores are mutated on the main thread (a finished dictation does `events.append`),
    /// and a concurrent background read of the same Array/Dictionary would be a data race (UB). The only
    /// work left for the background queue is the slow model call, over captured-by-value strings.
    /// `force` is informational (both paths produce a fresh snapshot); the freshness gate is in the
    /// caller (`refreshIfNeeded`), so a future cancel/coalesce can hook in here.
    private func generate(force: Bool) {
        if isGenerating { return } // one pass at a time — a second tap is a no-op
        isGenerating = true
        lastError = nil
        let inputs = Self.gatherInputs()   // main-thread read of InsightStore/Lexicon, captured by value
        queue.async { [weak self] in
            guard let self else { return }
            // Background: ONLY the model call, over the captured strings — no shared state is touched.
            let summary = Self.summarize(facts: inputs.facts, fallback: inputs.fallback)
            let snap = AISnapshot(
                generatedAt: Date().timeIntervalSince1970,
                windowHash: inputs.windowHash,
                summary: summary,
                nudges: inputs.nudges,
                suggestions: inputs.suggestions)
            DispatchQueue.main.async {
                self.snapshot = snap
                self.isGenerating = false
                self.save()
            }
        }
    }

    /// Everything a snapshot needs from the (main-thread-owned) stores, captured by value so the
    /// background pass is race-free: the window fingerprint, the deterministic suggestions + nudges, and
    /// the summary's aggregate `facts` string plus its deterministic `fallback`. Call on the main thread.
    private struct Inputs {
        let windowHash: String
        let facts: String
        let fallback: String
        let nudges: [String]
        let suggestions: [AISuggestion]
    }
    private static func gatherInputs() -> Inputs {
        Inputs(windowHash: windowHash(),
               facts: summaryFacts(),
               fallback: templateSummary(),
               nudges: buildNudges(),
               suggestions: buildSuggestions())
    }

    // MARK: window hash

    /// A cheap, deterministic fingerprint of the data window — count, total words, and the timestamp of
    /// the most recent event. Cheap to compute, and it changes exactly when new dictation arrives, which
    /// is the only time the summary could say something new.
    private static func windowHash() -> String {
        let store = InsightStore.shared
        let last = store.dictations.map { $0.ts }.max() ?? 0
        return "\(store.dictations.count)-\(store.totalWords)-\(Int(last))"
    }

    // MARK: suggestions (deterministic)

    /// DETERMINISTIC-FIRST: build suggested rules straight from `Lexicon.pending` — corrections you've
    /// made toward the same target but that haven't yet crossed the learn threshold. No model needed, so
    /// this works in stats-only mode. Most-corrected first; pick a representative mis-hearing as `from`.
    private static func buildSuggestions() -> [AISuggestion] {
        Lexicon.shared.pending
            .sorted { $0.value.count > $1.value.count }
            .compactMap { key, target -> AISuggestion? in
                guard let from = target.froms.sorted().first else { return nil }
                let times = target.count == 1 ? "once" : "\(target.count)×"
                return AISuggestion(
                    id: key,
                    from: from,
                    to: target.to,
                    reason: "You've corrected this \(times) — make it a rule?")
            }
    }

    // MARK: nudges (deterministic)

    /// DETERMINISTIC: 1–3 short, factual insights computed from `InsightStore` stats. The numbers are
    /// always real (no model) — a streak edge, the fastest-vs-slowest app by WPM, and this-week vs
    /// last-week word count. Kept terse and warm.
    private static func buildNudges() -> [String] {
        let store = InsightStore.shared
        var out: [String] = []

        // Streak edge: you're 1–6 days into a streak — one more lands the week.
        let streak = store.dayStreak
        if (1...6).contains(streak) {
            out.append("\(streak)-day streak — one more for a week.")
        }

        // Fastest vs slowest app by WPM (need ≥2 apps with timed dictation to compare).
        let paces = appPaces(store)
        if paces.count >= 2, let fast = paces.first, let slow = paces.last, fast.wpm > slow.wpm {
            // Broken into steps on purpose: a single nested numeric literal expression trips Swift's
            // "unable to type-check in reasonable time" budget.
            let ratio = Double(fast.wpm) / Double(max(1, slow.wpm))
            let pct = Int((ratio - 1) * 100)
            if pct >= 10 {
                out.append("You dictate \(pct)% faster in \(fast.name) than \(slow.name).")
            }
        }

        // This-week vs last-week word count (the last 14 days, split into two 7-day halves).
        let (thisWeek, lastWeek) = weekOverWeekWords(store)
        if lastWeek > 0 {
            let delta = thisWeek - lastWeek
            let pct = Int((Double(delta) / Double(lastWeek) * 100).rounded())
            if abs(pct) >= 10 {
                out.append(delta >= 0
                    ? "Up \(pct)% in words this week vs last."
                    : "Down \(abs(pct))% in words this week vs last.")
            }
        } else if thisWeek > 0 {
            out.append("\(InsightStore.compact(thisWeek)) words this week.")
        }

        return Array(out.prefix(3))
    }

    /// Per-app WPM over timed dictations, fastest first — the basis for the fastest-vs-slowest nudge.
    /// Only apps with a real recorded duration count (so WPM is meaningful).
    private static func appPaces(_ store: InsightStore) -> [(name: String, wpm: Int)] {
        var words: [String: Int] = [:], ms: [String: Int] = [:], name: [String: String] = [:]
        for e in store.dictations where e.durationMs > 0 {
            let key = e.appBundleId ?? e.appName ?? "Unknown"
            words[key, default: 0] += e.words
            ms[key, default: 0] += e.durationMs
            if let n = e.appName { name[key] = n } else if name[key] == nil { name[key] = key }
        }
        return words.keys.compactMap { key -> (name: String, wpm: Int)? in
            let minutes = Double(ms[key] ?? 0) / 60_000.0
            guard minutes > 0 else { return nil }
            return (name[key] ?? key, Int((Double(words[key] ?? 0) / minutes).rounded()))
        }
        .sorted { $0.wpm > $1.wpm }
    }

    /// Words in the last 7 days vs the 7 before that, off `wordsPerDay` (already last-30-days, zero-
    /// filled). The last 7 entries are this week; the 7 before are last week.
    private static func weekOverWeekWords(_ store: InsightStore) -> (thisWeek: Int, lastWeek: Int) {
        let days = store.wordsPerDay
        guard !days.isEmpty else { return (0, 0) }
        let thisWeek = Int(days.suffix(7).reduce(0) { $0 + $1.value })
        let prior = days.count >= 14 ? Array(days.suffix(14).prefix(7)) : []
        let lastWeek = Int(prior.reduce(0) { $0 + $1.value })
        return (thisWeek, lastWeek)
    }

    // MARK: summary (generative, with deterministic fallback)

    /// System prompt for the summary: a few warm, factual sentences over aggregate numbers, no preamble.
    /// Tight on purpose — the 1.5B model only phrases data we hand it; it never sees the transcript log.
    private static let summarySystem = """
    You write a short, warm weekly recap of someone's dictation activity from the numbers given. Write \
    2–3 plain sentences in second person ("you"). Be factual and specific to the numbers — do not invent \
    figures, do not give advice, do not add a greeting or sign-off. Reply with ONLY the recap, nothing \
    else (no preamble, no quotes, no headings).
    """

    /// The one generative piece — runs on the background queue over the already-captured `facts`
    /// (aggregates only, never the raw transcript log). Ask the warm model to phrase them; clip the
    /// output; on any failure/empty return the deterministic `fallback` so the card is always populated.
    /// Safe off the main thread: `WarmLLM` touches only the filesystem + a loopback server, not the
    /// shared stores (those were read on main, in `gatherInputs`).
    private static func summarize(facts: String, fallback: String) -> String {
        guard WarmLLM.isInstalled() else { return fallback }
        guard let raw = WarmLLM.shared.generate(system: summarySystem, text: facts, timeout: 30) else {
            return fallback
        }
        let clipped = LLMPolish.clip(raw)
        return clipped.isEmpty ? fallback : clipped
    }

    /// The aggregate facts handed to the model — a tidy `key: value` list, numbers only. Never includes
    /// any transcript text, so the summary is identical whether History is on or off.
    private static func summaryFacts() -> String {
        let store = InsightStore.shared
        var lines: [String] = []
        lines.append("Total words dictated: \(store.totalWords)")
        if store.avgWPM > 0 { lines.append("Average speaking pace: \(store.avgWPM) words per minute") }
        if store.dayStreak > 0 { lines.append("Current daily streak: \(store.dayStreak) days") }
        let topApps = store.perApp.prefix(3).map { "\($0.name) (\($0.words) words)" }
        if !topApps.isEmpty { lines.append("Most-used apps: \(topApps.joined(separator: ", "))") }
        let (thisWeek, lastWeek) = weekOverWeekWords(store)
        lines.append("Words this week: \(thisWeek)")
        lines.append("Words last week: \(lastWeek)")
        return lines.joined(separator: "\n")
    }

    /// The deterministic recap used when the model is unavailable or returns nothing — plain, factual,
    /// and never empty. Same aggregates as the prompt.
    private static func templateSummary() -> String {
        let store = InsightStore.shared
        guard store.totalWords > 0 else {
            return "No dictation yet — your recap will appear here once you've dictated a few times."
        }
        var parts: [String] = []
        parts.append("You've dictated \(InsightStore.compact(store.totalWords)) words so far")
        if store.avgWPM > 0 { parts.append("at about \(store.avgWPM) words per minute") }
        var first = parts.joined(separator: " ") + "."
        if store.dayStreak > 0 {
            first += " You're on a \(store.dayStreak)-day streak."
        }
        if let top = store.perApp.first {
            first += " Most of it lands in \(top.name)."
        }
        return first
    }

    // MARK: accept / dismiss

    /// Accept a suggested rule: promote it via `Lexicon.learn(from:to:)` and drop it from the snapshot so
    /// it stops showing. Persisted.
    func acceptSuggestion(_ s: AISuggestion) {
        Lexicon.shared.learn(from: s.from, to: s.to)
        removeSuggestion(s)
    }

    /// Dismiss a suggested rule: drop it from the snapshot without learning it. Persisted.
    func dismissSuggestion(_ s: AISuggestion) {
        removeSuggestion(s)
    }

    /// Remove one suggestion from the current snapshot (rewriting the snapshot in place) and persist.
    private func removeSuggestion(_ s: AISuggestion) {
        guard let cur = snapshot else { return }
        snapshot = AISnapshot(
            generatedAt: cur.generatedAt,
            windowHash: cur.windowHash,
            summary: cur.summary,
            nudges: cur.nudges,
            suggestions: cur.suggestions.filter { $0.id != s.id })
        save()
    }

    // MARK: persistence (mirrors InsightStore: 0600, atomic)

    /// Load the cached snapshot from ~/.warble/insights-ai.json. Absent/corrupt → start empty (the auto
    /// path will regenerate when eligible).
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        snapshot = try? JSONDecoder().decode(AISnapshot.self, from: data)
    }

    /// Persist the current snapshot — a plain local JSON file you can read, export, or delete. Atomic
    /// write + 0600, the same hygiene as the rest of ~/.warble.
    private func save() {
        guard let snap = snapshot else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
