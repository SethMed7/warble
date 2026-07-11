import AppKit
import ApplicationServices

/// Headless entries for the dictation pipeline (CI / dev smoke tests). No UI, no hotkey.
/// `--clean`, `--cleanup`, `--cleanup-level`, `--polish`, `--transcribe`, `--engine`, `--apply`,
/// `--selftest`, `--axcheck`, `--learn-test`, `--recover-scan`, `--hold-cap`, `--hold-cap-sim`.
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
            var outcome = Transcribers.Outcome.failed
            // Completion posts to the main queue; run the main loop so it can drain.
            Transcribers.run(wav, clipDuration: 10) { o in outcome = o; CFRunLoopStop(CFRunLoopGetMain()) }
            CFRunLoopRunInMode(.defaultMode, 60, false)
            switch outcome {
            case .text(let t): print(t)
            case .silence: print("") // ran fine, heard nothing — same output the old smoke expected
            case .failed:
                // The flow's named cause, minus "recording kept" (the CLI owns no recording).
                // regression.sh forces this branch with WARBLE_FAULT=transcribe-fail.
                FileHandle.standardError.write(Data("\(DictateError.transcribeFailed.message)\n".utf8))
                exit(1)
            }
            return true
        }
        if args.contains("--engine") {
            let name = Transcribers.activeEngineName()
            if name == "Apple Speech" { // name the floor's cause, off stdout so smokes stay exact
                FileHandle.standardError.write(Data("\(DictateError.engineMissing.message)\n".utf8))
            }
            print(name)
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
        if args.contains("--hold-cap") {
            // Long-session hardening (ROADMAP 0.3): print the resolved cap story — the cap, when
            // the pill's countdown starts, and the named stop cause. WARBLE_MAX_HOLD_SECS (debug
            // builds only) compresses it; regression.sh asserts both forms exactly.
            let cap = HoldCap.maxSeconds
            let warnAt = Int(cap - HoldCap.warnWindow(for: cap))
            print("cap \(Int(cap))s · warn at \(warnAt)s · on stop: \(DictateError.holdCapReached.message)")
            return true
        }
        if args.contains("--hold-cap-sim") {
            // Drive the REAL session clock (HoldCapClock — the machine the pill countdown and the
            // clean cap-stop hang off) at a compressed cap and print its events. Proves headlessly
            // that the warning ticks before the cap and that the cap actually fires; exits
            // non-zero if the cap arrives with no warning tick.
            let cap = HoldCap.maxSeconds
            guard cap <= 60 else {
                FileHandle.standardError.write(Data("--hold-cap-sim needs a compressed cap — set WARBLE_MAX_HOLD_SECS (≤60)\n".utf8))
                exit(2)
            }
            var ticks = 0
            var done = false
            let clock = HoldCapClock(onTick: { secs in ticks += 1; print("warn \(secs)") },
                                     onCap: { done = true; CFRunLoopStop(CFRunLoopGetMain()) })
            defer { clock.cancel() }
            while !done { CFRunLoopRunInMode(.defaultMode, 120, false) }
            guard ticks > 0 else {
                FileHandle.standardError.write(Data("capped with no warning tick\n".utf8))
                exit(1)
            }
            print("capped")
            return true
        }
        if args.contains("--recover-scan") {
            // Dictation recovery, headless (ROADMAP 0.3; asserted by regression.sh): exactly what
            // the app does — the launch scan plus the menu's Recover action — minus the UI.
            // WARBLE_HOME sandboxes the store; WARBLE_FAULT=transcribe-fail forces the FAILED-event
            // path so the check needs no engines. Output is stable lines the script matches.
            guard let orphan = Recovery.scan() else {
                print("no in-flight dictation found")
                return true
            }
            var done = false
            Recovery.recover(orphan) { outcome in
                switch outcome {
                case .recovered(let text):
                    print("recovered (\(InsightStore.wordCount(text)) words) — it's in History")
                case .failedKept(let duration, let audio):
                    print("recovered as failed event — audio kept (\(String(format: "%.1f", duration))s)")
                    print("audio: \(audio.path)")
                case .failedLost:
                    print("transcription failed — audio not kept (saving off / secure)")
                case .nothingHeard:
                    print("nothing heard — in-flight clip discarded")
                }
                done = true
                CFRunLoopStop(CFRunLoopGetMain())
            }
            // Completions hop the main queue; pump the run loop until recovery finishes.
            while !done { CFRunLoopRunInMode(.defaultMode, 120, false) }
            return true
        }
        return false
    }

    /// The dictate half of `--errors` (dispatched in main.swift): one "dictate/<reason>: <copy>"
    /// line per taxonomy case. regression.sh asserts the table verbatim — copy drift is deliberate.
    public static func printErrors() {
        for e in DictateError.allCases { print("dictate/\(e.reason): \(e.message)") }
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
                                     appBundleId: nil, appName: nil, engine: "test", kind: "dictate",
                                     status: nil)
        let rebuilt = (try? JSONEncoder().encode(withRaw))
            .flatMap { try? JSONDecoder().decode(DictationEvent.self, from: $0) }
        check(rebuilt?.raw == "um so the the report", "raw transcript round-trips through a history line")
        check(decoded?.isFailed == false, "pre-recovery history line decodes as not-failed")

        // A FAILED event (dictation recovery, ROADMAP 0.3) must round-trip its status.
        let failed = DictationEvent(id: "z", ts: 3, day: "2026-07-11", text: "", raw: nil, words: 0,
                                    durationMs: 1200, appBundleId: nil, appName: nil, engine: "test",
                                    kind: "dictate", status: "failed")
        let failedBack = (try? JSONEncoder().encode(failed))
            .flatMap { try? JSONDecoder().decode(DictationEvent.self, from: $0) }
        check(failedBack?.isFailed == true, "failed status round-trips through a history line")

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
