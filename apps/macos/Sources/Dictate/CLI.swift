import AppKit
import ApplicationServices

/// Headless entries for the dictation pipeline (CI / dev smoke tests). No UI, no hotkey.
/// `--clean`, `--cleanup`, `--cleanup-level`, `--polish`, `--transcribe`, `--engine`, `--apply`,
/// `--selftest`, `--axcheck`, `--learn-test`.
public enum DictateCLI {
    /// Returns true if it handled the args (the caller should then exit).
    public static func handle(_ args: [String]) -> Bool {
        if args.contains("--axcheck") {
            // Does THIS app have Accessibility? (no prompt) — auto-paste AND learn-from-edits need it.
            print(AXIsProcessTrusted() ? "accessibility: GRANTED" : "accessibility: NOT granted")
            return true
        }
        if args.contains("--axprobe") {
            // Focus the app/field to test (e.g. Claude Code in Ghostty), then we report what warble can read.
            FileHandle.standardError.write(Data("Focus the field to test (e.g. Claude Code in Ghostty)… probing in 4s\n".utf8))
            Thread.sleep(forTimeInterval: 4)
            print(CorrectionListener.probe())
            return true
        }
        if let i = args.firstIndex(of: "--learn-test"), i + 2 < args.count {
            // Prove the frequency tally headlessly. Point WARBLE_DICTIONARY at a temp file to avoid
            // touching your real dictionary: WARBLE_DICTIONARY=/tmp/t.json warble --learn-test deval Dhaval
            let from = args[i + 1], to = args[i + 2]
            Lexicon.shared.load()
            let threshold = Lexicon.shared.learnThreshold
            print("threshold = \(threshold); simulating \(threshold) identical fixes of \(from) → \(to)")
            for n in 1...threshold {
                switch Lexicon.shared.recordCorrection(from: from, to: to) {
                case .promoted(let w):              print("  fix #\(n): PROMOTED → rule '\(from.lowercased())' → '\(w)'")
                case .pending(let w, let c, let t): print("  fix #\(n): pending '\(w)' (\(c) of \(t))")
                case .ignored:                      print("  fix #\(n): ignored")
                }
            }
            print("dictionary now maps '\(from.lowercased())' → \(Lexicon.shared.corrections[from.lowercased()] ?? "(none)")")
            return true
        }
        if let i = args.firstIndex(of: "--clean"), i + 1 < args.count {
            print(BasicCleaner.cleaned(args[i + 1])) // deterministic pass only
            return true
        }
        if let i = args.firstIndex(of: "--cleanup"), i + 2 < args.count {
            // Run the cleanup pipeline at an explicit level: none/light are engine-free and exact;
            // medium/high use the on-device LLM when installed and otherwise report the fallback
            // honestly (stderr) while printing the deterministic result — never a hard failure.
            guard let level = CleanupLevel(rawValue: args[i + 1].lowercased()) else {
                FileHandle.standardError.write(Data("unknown cleanup level \"\(args[i + 1])\" — use none|light|medium|high\n".utf8))
                exit(2)
            }
            if level.usesLLM, !Cleaners.llmAvailable {
                FileHandle.standardError.write(Data("note: no on-device LLM installed — \(level.rawValue) falls back to the deterministic result\n".utf8))
            }
            print(Cleaners.cleaner(at: level, for: args[i + 2]).clean(args[i + 2]))
            return true
        }
        if let i = args.firstIndex(of: "--cleanup-level") {
            // Get (no value) or set (with a value) the persisted cleanup level; always prints the
            // resulting level, so a set in one process and a get in the next proves the
            // UserDefaults round-trip headlessly.
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                guard let level = CleanupLevel(rawValue: args[i + 1].lowercased()) else {
                    FileHandle.standardError.write(Data("unknown cleanup level \"\(args[i + 1])\" — use none|light|medium|high\n".utf8))
                    exit(2)
                }
                Cleaners.level = level
            }
            print(Cleaners.level.rawValue)
            return true
        }
        if let i = args.firstIndex(of: "--spell"), i + 1 < args.count {
            let r = SpellOut.process(args[i + 1])
            print("text:  \(r.text)")
            for rule in r.learned { print("learn: \(rule.from) -> \(rule.to)") }
            return true
        }
        if let i = args.firstIndex(of: "--polish"), i + 1 < args.count {
            // Full cleaner chain at Medium (regardless of the persisted level — it's the LLM-path
            // smoke): the on-device LLM when installed, else deterministic.
            print(Cleaners.cleaner(at: .medium, for: nil).clean(args[i + 1]))
            return true
        }
        if let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count {
            let wav = URL(fileURLWithPath: args[i + 1])
            var result = ""
            // Completion posts to the main queue; run the main loop so it can drain.
            Transcribers.run(wav, clipDuration: 10) { text in result = text; CFRunLoopStop(CFRunLoopGetMain()) }
            CFRunLoopRunInMode(.defaultMode, 60, false)
            print(result)
            return true
        }
        if args.contains("--engine") {
            print(Transcribers.activeEngineName())
            return true
        }
        if let i = args.firstIndex(of: "--apply"), i + 1 < args.count {
            Lexicon.shared.load() // honors DICTADO_DICTIONARY for a non-default location
            print(Lexicon.shared.apply(args[i + 1]))
            return true
        }
        if args.contains("--selftest") {
            runSelftest()
            return true
        }
        return false
    }

    /// Verify the learn-from-edits detection logic and history-event codability headlessly.
    private static func runSelftest() {
        var fails = 0
        func check(_ ok: Bool, _ name: String) { print((ok ? "ok   " : "FAIL ") + name); if !ok { fails += 1 } }

        // History events: a pre-0.3 line (no `raw`) must still decode, and the raw transcript
        // (undo-polish, ROADMAP 0.3) must survive an encode/decode round-trip.
        let legacy = #"{"id":"x","ts":1,"day":"2026-07-11","text":"so the report","words":3,"durationMs":900,"engine":"test","kind":"dictate"}"#
        let decoded = try? JSONDecoder().decode(DictationEvent.self, from: Data(legacy.utf8))
        check(decoded != nil && decoded?.raw == nil, "pre-0.3 history line decodes (raw nil)")
        let withRaw = DictationEvent(id: "y", ts: 2, day: "2026-07-11", text: "so the report",
                                     raw: "um so the the report", words: 3, durationMs: 900,
                                     appBundleId: nil, appName: nil, engine: "test", kind: "dictate")
        let rebuilt = (try? JSONEncoder().encode(withRaw))
            .flatMap { try? JSONDecoder().decode(DictationEvent.self, from: $0) }
        check(rebuilt?.raw == "um so the the report", "raw transcript round-trips through a history line")

        check(CorrectionListener.levenshtein("miele", "myela") == 2, "levenshtein miele/myela == 2")
        check(CorrectionListener.levenshtein("cat", "cat") == 0, "levenshtein identical == 0")

        let d1 = CorrectionListener.detectCorrection(
            baseline: ["ship", "the", "miele", "engine", "today"],
            current: ["ship", "the", "myela", "engine", "today"],
            pasted: ["ship", "the", "miele", "engine", "today"])
        check(d1?.0.lowercased() == "miele" && d1?.1 == "myela", "detects miele -> myela")

        check(CorrectionListener.detectCorrection(baseline: ["the", "cat", "sat"], current: ["the", "dog", "sat"],
            pasted: ["the", "cat", "sat"]) == nil, "ignores cat -> dog rephrase")

        check(CorrectionListener.detectCorrection(baseline: ["hello", "wrold", "there"], current: ["hello", "world", "there"],
            pasted: ["hello", "there"]) == nil, "ignores fix of a word we didn't type")

        check(CorrectionListener.detectCorrection(baseline: ["aa", "bb", "cc"], current: ["xx", "bb", "yy"],
            pasted: ["aa", "bb", "cc"]) == nil, "ignores multi-word change")

        print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
    }
}
