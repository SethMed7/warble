import AppKit

extension Notification.Name {
    /// Posted by `InsightStore.clearAll()` so derived local caches (the Insights AI snapshot) wipe in lockstep.
    static let warbleInsightsCleared = Notification.Name("warble.insightsCleared")
    /// Posted when `autoUpdateEnabled` changes so the app target's Sparkle updater applies it immediately.
    public static let warbleAutoUpdateChanged = Notification.Name("warble.autoUpdateChanged")
}

/// The local store behind warble Insights, all under ~/.warble:
///   history.json   — append-only JSON-Lines log of dictations (text + metrics)
///   audio/<id>.m4a — the saved recording for each dictation (when audio-saving is on);
///                    16 kHz mono AAC. Pre-0.1.8 installs have raw <id>.wav — still read.
///   dictionary.json — the user dictionary (owned by Lexicon)
/// Loaded into memory; mirrors the dependency-free on-disk pattern Lexicon already uses. Everything
/// is local — never uploaded.
public final class InsightStore: ObservableObject {
    public static let shared = InsightStore()

    @Published private(set) var events: [DictationEvent] = []

    /// When off (stats-only), the transcript text isn't written to disk — every metric still is.
    var historyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "insightsHistory") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "insightsHistory") }
    }
    /// Keep the recording so you can replay/relisten. Off → audio is deleted as before (nothing saved).
    var saveAudio: Bool {
        get { UserDefaults.standard.object(forKey: "insightsSaveAudio") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "insightsSaveAudio") }
    }
    /// Never store text/audio when a secure (password) field is focused. Default on.
    var excludeSecureFields: Bool {
        get { UserDefaults.standard.object(forKey: "insightsExcludeSecure") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "insightsExcludeSecure") }
    }
    /// The Insights AI master switch. Off (default) → the on-device summary/suggestions/nudges layer
    /// never spawns or calls the model; the AI cards stay dark. Opt-in. The setter fires
    /// `objectWillChange` because these flags are read ACROSS views (the AI cards + the dependent
    /// Data & Privacy row) — without it, flipping a UserDefaults-backed computed prop wouldn't re-render.
    var aiInsightsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "insightsAI") as? Bool ?? false }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "insightsAI") }
    }
    /// Once AI is on, regenerate automatically when the Insights tab opens and the cache is stale.
    /// Off → on-demand only (the "Regenerate" button is the sole trigger). Default on.
    var aiInsightsAutoRefresh: Bool {
        get { UserDefaults.standard.object(forKey: "insightsAIAuto") as? Bool ?? true }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "insightsAIAuto") }
    }
    /// Whether warble checks for app updates automatically (the quiet ~daily background check). The
    /// "Check for Updates…" menu item is always available regardless. Default on. The app target's
    /// Sparkle updater syncs to this — the setter posts `.warbleAutoUpdateChanged` so it applies at once.
    public var autoUpdateEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "warbleAutoUpdate") as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "warbleAutoUpdate")
            NotificationCenter.default.post(name: .warbleAutoUpdateChanged, object: nil)
        }
    }

    let dir: URL          // ~/.warble
    private let fileURL: URL    // ~/.warble/history.json
    private let audioDir: URL   // ~/.warble/audio

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f // local timezone by default — the streak key
    }()

    private init() {
        dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".warble")
        fileURL = dir.appendingPathComponent("history.json")
        audioDir = dir.appendingPathComponent("audio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        load()
    }

    // MARK: record

    /// Persist one dictation. `audioSource` is the temp WAV (still on disk); we encode it into the
    /// store when audio-saving is on. The caller deletes the temp WAV as soon as this returns, so the
    /// encode must complete synchronously here.
    func record(_ cleaned: String, ctx: DictationContext, audioSource: URL?) {
        let text = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = UUID().uuidString
        let blocked = ctx.secure && excludeSecureFields   // password field focused → keep metrics only
        if saveAudio, !blocked, let src = audioSource {
            // 16 kHz mono AAC — ~25x smaller than the raw device-rate float WAV.
            let dest = audioDir.appendingPathComponent("\(id).m4a")
            if AudioConvert.to16kMonoAAC(input: src, output: dest) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
            } else {
                // Encoder failure must not lose the recording — keep the raw copy like before.
                let wav = audioDir.appendingPathComponent("\(id).wav")
                try? FileManager.default.copyItem(at: src, to: wav)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: wav.path)
            }
        }
        let e = DictationEvent(
            id: id,
            ts: Date().timeIntervalSince1970,
            day: Self.dayFormatter.string(from: Date()),
            text: (historyEnabled && !blocked) ? text : "",
            words: Self.wordCount(text),
            durationMs: ctx.durationMs,
            appBundleId: ctx.appBundleId,
            appName: ctx.appName,
            engine: ctx.engine,
            kind: "dictate")
        events.append(e)
        appendLine(e)
    }

    static func wordCount(_ s: String) -> Int {
        s.split { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }.count
    }

    /// Log a read-aloud selection (kind "read"). No recording duration (it's TTS), so it never affects
    /// WPM. Public so the read-aloud side (a separate module) can route reads in via the app coordinator.
    public func recordRead(text: String, appBundleId: String?, appName: String?, voice: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let e = DictationEvent(
            id: UUID().uuidString,
            ts: Date().timeIntervalSince1970,
            day: Self.dayFormatter.string(from: Date()),
            text: historyEnabled ? t : "",
            words: Self.wordCount(t),
            durationMs: 0,
            appBundleId: appBundleId,
            appName: appName,
            engine: voice,
            kind: "read")
        events.append(e)
        appendLine(e)
    }

    // MARK: edit / delete (used from the History detail — "go train it")

    /// The saved recording for an event, if audio-saving kept it. .m4a is the current format;
    /// .wav covers recordings saved before the AAC switch.
    func audioURL(for e: DictationEvent) -> URL? {
        for ext in ["m4a", "wav"] {
            let u = audioDir.appendingPathComponent("\(e.id).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Correct a stored transcript (recomputes word count) and persist.
    func updateText(_ id: String, to newText: String) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        let o = events[i]
        events[i] = DictationEvent(id: o.id, ts: o.ts, day: o.day, text: newText,
                                   words: Self.wordCount(newText), durationMs: o.durationMs,
                                   appBundleId: o.appBundleId, appName: o.appName, engine: o.engine, kind: o.kind)
        rewrite()
    }

    func delete(_ e: DictationEvent) {
        for ext in ["m4a", "wav"] { // whichever format this event's recording was saved in
            try? FileManager.default.removeItem(at: audioDir.appendingPathComponent("\(e.id).\(ext)"))
        }
        events.removeAll { $0.id == e.id }
        rewrite()
    }

    /// Wipe every transcript and recording — AND the derived Insights AI cache (the Data & Privacy
    /// "Clear all" promises everything goes). Deletes the AI file directly (true even if the AI view was
    /// never opened) and posts `.warbleInsightsCleared` so a live `AIInsightsStore` drops its in-memory copy.
    func clearAll() {
        events.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: audioDir)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("insights-ai.json"))
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        NotificationCenter.default.post(name: .warbleInsightsCleared, object: nil)
    }

    /// All events as a pretty JSON array, for Export.
    func exportJSON() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(events)) ?? Data("[]".utf8)
    }

    /// "N recordings · X MB" for the Data panel — both the current .m4a and legacy .wav count.
    var audioSummary: String {
        let files = (try? FileManager.default.contentsOfDirectory(at: audioDir,
                     includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let clips = files.filter { ["m4a", "wav"].contains($0.pathExtension) }
        let bytes = clips.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return "\(clips.count) recordings · \(String(format: "%.1f", Double(bytes) / 1_048_576.0)) MB"
    }

    // MARK: derived stats

    var dictations: [DictationEvent] { events.filter { $0.kind == "dictate" } }
    var reads: [DictationEvent] { events.filter { $0.kind == "read" } }
    var totalWords: Int { dictations.reduce(0) { $0 + $1.words } }   // words you dictated
    var wordsRead: Int { reads.reduce(0) { $0 + $1.words } }         // words read aloud

    var dayStreak: Int {
        guard !events.isEmpty else { return 0 }
        let days = Set(events.map { $0.day })
        let cal = Calendar.current
        var cursor = Date()
        if !days.contains(Self.dayFormatter.string(from: cursor)) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        while days.contains(Self.dayFormatter.string(from: cursor)) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    var avgWPM: Int {
        let timed = events.filter { $0.kind == "dictate" && $0.durationMs > 0 }
        let minutes = Double(timed.reduce(0) { $0 + $1.durationMs }) / 60_000.0
        guard minutes > 0 else { return 0 }
        return Int((Double(timed.reduce(0) { $0 + $1.words }) / minutes).rounded())
    }

    var totalWordsCompact: String { Self.compact(totalWords) }
    var wordsReadCompact: String { Self.compact(wordsRead) }
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Per-app usage ("where I use it"), most-used first.
    struct AppUsage: Identifiable { let id: String; let name: String; let words: Int; let count: Int }
    var perApp: [AppUsage] {
        var map: [String: (name: String, words: Int, count: Int)] = [:]
        for e in events where e.kind == "dictate" {
            let key = e.appBundleId ?? e.appName ?? "Unknown"
            var cur = map[key] ?? (e.appName ?? key, 0, 0)
            cur.words += e.words; cur.count += 1
            if let n = e.appName { cur.name = n }
            map[key] = cur
        }
        return map.map { AppUsage(id: $0.key, name: $0.value.name, words: $0.value.words, count: $0.value.count) }
            .sorted { $0.words > $1.words }
    }

    /// Distinct apps across ALL events (dictate + read), for the History filter — the feed shows both,
    /// so the filter must too (perApp is dictate-only for the "where you dictate" widget).
    var appFilters: [(key: String, name: String)] {
        var seen: [String: String] = [:]
        for e in events {
            let key = e.appBundleId ?? e.appName ?? "Unknown"
            if seen[key] == nil { seen[key] = e.appName ?? key }
        }
        return seen.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }

    // MARK: chart series (last 30 days)

    struct DayStat: Identifiable { let id: String; let date: Date; let value: Double }

    private func lastDays(_ n: Int) -> [(date: Date, key: String)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<n).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (d, Self.dayFormatter.string(from: d))
        }
    }

    /// Words dictated per day (zeros included so the bar chart shows gaps).
    var wordsPerDay: [DayStat] {
        var map: [String: Int] = [:]
        for e in dictations { map[e.day, default: 0] += e.words }
        return lastDays(30).map { DayStat(id: $0.key, date: $0.date, value: Double(map[$0.key] ?? 0)) }
    }

    /// Average WPM per day — only days you actually dictated (so the trend line connects real points).
    var wpmPerDay: [DayStat] {
        var words: [String: Int] = [:], ms: [String: Int] = [:]
        for e in dictations where e.durationMs > 0 {
            words[e.day, default: 0] += e.words
            ms[e.day, default: 0] += e.durationMs
        }
        return lastDays(30).compactMap { day in
            let minutes = Double(ms[day.key] ?? 0) / 60_000.0
            guard minutes > 0 else { return nil }
            return DayStat(id: day.key, date: day.date, value: (Double(words[day.key] ?? 0) / minutes).rounded())
        }
    }

    // MARK: persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = String(data: data, encoding: .utf8) else { return }
        let dec = JSONDecoder()
        events = s.split(separator: "\n").compactMap { try? dec.decode(DictationEvent.self, from: Data($0.utf8)) }
    }

    private func appendLine(_ e: DictationEvent) {
        guard let json = try? JSONEncoder().encode(e),
              var line = String(data: json, encoding: .utf8) else { return }
        line += "\n"
        let bytes = Data(line.utf8)
        if let fh = try? FileHandle(forWritingTo: fileURL) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: bytes)
        } else {
            try? bytes.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }

    /// Rewrite the whole log (after an edit/delete). Fine at single-user volume.
    private func rewrite() {
        let enc = JSONEncoder()
        let lines = events.compactMap { e -> String? in
            guard let d = try? enc.encode(e) else { return nil }
            return String(data: d, encoding: .utf8)
        }
        let blob = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? Data(blob.utf8).write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
