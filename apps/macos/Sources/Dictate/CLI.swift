import AppKit
import ApplicationServices
import AVFoundation

/// Headless entries for the dictation pipeline (CI / dev smoke tests). No UI, no hotkey.
/// `--clean`, `--cleanup`, `--cleanup-level`, `--polish`, `--transcribe`, `--engine`, `--apply`,
/// `--expand`, `--snippet-set`, `--autosend`, `--bindings`, `--selftest`, `--axcheck`,
/// `--learn-test`, `--recover-scan`, `--retranscribe`, `--hold-cap`, `--hold-cap-sim`,
/// `--bench-e2e`, `--practice-sim`, `--sounds`, `--render-pill` (DEBUG).
public enum DictateCLI {
    /// Returns true if it handled the args (the caller should then exit).
    public static func handle(_ args: [String]) -> Bool {
        if let i = args.firstIndex(of: "--sounds") {
            // The listening contract's pings (ROADMAP 0.4). Get (no value) or set (on|off) the
            // preference; always prints the resulting state, so a set in one process and a get in
            // the next proves the UserDefaults round-trip headlessly (the --cleanup-level idiom).
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                switch args[i + 1] {
                case "on": DictateSounds.enabled = true
                case "off": DictateSounds.enabled = false
                default:
                    FileHandle.standardError.write(Data("unknown sounds value \"\(args[i + 1])\" — use on|off\n".utf8))
                    exit(2)
                }
            }
            print(DictateSounds.enabled ? "on" : "off")
            return true
        }
        #if DEBUG
        if let i = args.firstIndex(of: "--render-pill") {
            // The pill's UI-verification seam: rasterize any pill state offscreen at 2x.
            guard i + 2 < args.count else {
                FileHandle.standardError.write(Data("usage: --render-pill <state> <out.png>\n".utf8))
                exit(2)
            }
            Overlay.renderPill(args[i + 1], to: URL(fileURLWithPath: args[i + 2]))
            return true
        }
        #else
        if args.contains("--render-pill") {
            // Never fall through into launching the app because a QA flag hit a release build.
            FileHandle.standardError.write(Data("--render-pill exists in DEBUG builds only\n".utf8))
            exit(2)
        }
        #endif
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
        if let i = args.firstIndex(of: "--expand"), i + 1 < args.count {
            // Snippets (ROADMAP 0.5), headless: fixture triggers via WARBLE_HOME, same idiom as
            // --apply. Runs the matcher alone — the full leg order (cleanup -> dictionary ->
            // snippets) is what --bench-e2e and the real pipeline run.
            Snippets.shared.load()
            print(Snippets.shared.expand(args[i + 1]))
            return true
        }
        if let i = args.firstIndex(of: "--snippet-set"), i + 2 < args.count {
            // The dashboard's Add/Save action, headless: proves the write path end to end —
            // WARBLE_HOME relocation, the owner-only (0600) file, and that a later --expand in a
            // fresh process reads back exactly what was saved.
            Snippets.shared.load()
            Snippets.shared.set(trigger: args[i + 1], expansion: args[i + 2])
            print("saved '\(args[i + 1].lowercased())' -> \(Snippets.shared.fileURL.path)")
            return true
        }
        if let i = args.firstIndex(of: "--bindings") {
            // Multi-shortcut + mouse bindings (ROADMAP 0.5), headless. Bare `--bindings` prints
            // the active trigger table — the built-in Fn row first (it's law, not storage), then
            // each persisted binding. `add`/`remove <trigger:gesture>` run the dashboard editor's
            // exact validation path and persist through the same "warble" defaults domain the app
            // reads (the --cleanup-level idiom), so a set in one process and a table in the next
            // proves the round-trip; a rejected add prints the same plain reason the dashboard
            // shows and exits non-zero. No monitor is ever installed here — CLI modes are UI-free
            // by construction, and bindings only register while Dictate is on (HotKey.register).
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                guard i + 2 < args.count else {
                    FileHandle.standardError.write(Data("usage: --bindings [add|remove <trigger:gesture>]\n".utf8))
                    exit(2)
                }
                let spec = args[i + 2]
                switch args[i + 1] {
                case "add":
                    switch Bindings.shared.add(spec) {
                    case .added(let b): print("added \(b.trigger.spec) \(b.gesture.rawValue)")
                    case .rejected(let reason): print("rejected: \(reason)"); exit(1)
                    }
                case "remove":
                    guard case .ok(let b) = Bindings.parse(spec) else {
                        FileHandle.standardError.write(Data("unknown binding \"\(spec)\" — use trigger:gesture\n".utf8))
                        exit(2)
                    }
                    if Bindings.shared.remove(b) {
                        print("removed \(b.trigger.spec) \(b.gesture.rawValue)")
                    } else {
                        print("not bound")
                        exit(1)
                    }
                default:
                    FileHandle.standardError.write(Data("unknown --bindings verb \"\(args[i + 1])\" — use add|remove\n".utf8))
                    exit(2)
                }
                return true
            }
            print("fn hold+double-tap (built in)")
            for b in Bindings.shared.list { print("\(b.trigger.spec) \(b.gesture.rawValue)") }
            return true
        }
        if let i = args.firstIndex(of: "--autosend"), i + 1 < args.count {
            // "Press enter" auto-send (ROADMAP 0.5), headless: reads the CURRENT persisted toggle
            // (the "warble" defaults domain — same seam as --cleanup-level/--sounds), so a
            // `defaults write warble autoSendEnabled -bool true` in the shell before this call
            // proves the ON path, and the toggle's OFF default needs no setup at all. Runs on
            // already-cleaned input — the real pipeline runs cleanup -> dictionary -> snippets
            // first (see transcribeAndDeliver); this flag is the auto-send leg alone.
            let r = AutoSend.apply(args[i + 1])
            print("send: \(r.send ? "yes" : "no")")
            print("pasted: \(r.pasted)")
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
        if let i = args.firstIndex(of: "--bench-e2e"), i + 1 < args.count {
            // Benchmark harness (scripts/bench/latency.sh → docs/benchmarks.md): time the paste
            // path a scripted run can reach — WAV → transcribe → spell → clean → dictionary →
            // paste-ready string, the exact leg order of DictateController's transcribeAll — N
            // times in ONE process, so run 1 pays any engine cold start and later runs are warm.
            // Excluded by construction (docs/benchmarks.md estimates them): key handling, recorder
            // finalize, and the paste event itself. WARBLE_FORCE_ENGINE (debug seam) pins the
            // engine. Exits non-zero if any run failed, so scripts can trust parsed numbers.
            benchE2E(wav: URL(fileURLWithPath: args[i + 1]),
                     runs: (i + 2 < args.count ? Int(args[i + 2]) : nil).map { max(1, $0) } ?? 1)
        }
        if let i = args.firstIndex(of: "--practice-sim"), i + 1 < args.count {
            practiceSim(wav: URL(fileURLWithPath: args[i + 1]))
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
        if args.contains("--retranscribe") {
            // The History "Re-transcribe" action, headless (ROADMAP 0.3 recovery; asserted by
            // regression.sh): run the pipeline again over the newest FAILED event's kept recording
            // and resolve it in place. WARBLE_HOME sandboxes the store; WARBLE_FORCE_ENGINE=stub
            // makes it engine-free. Exits non-zero when the event stays failed.
            guard let failed = InsightStore.shared.events.last(where: { $0.isFailed }) else {
                print("no failed dictation found")
                return true
            }
            var done = false
            Recovery.retranscribe(failed) { outcome in
                switch outcome {
                case .text(let cleaned, _):
                    print("re-transcribed (\(InsightStore.wordCount(cleaned)) words) — resolved in place")
                case .silence:
                    print("nothing heard — still marked failed")
                    exit(1)
                case .failed:
                    FileHandle.standardError.write(Data("\(DictateError.transcribeFailed.message)\n".utf8))
                    exit(1)
                }
                done = true
                CFRunLoopStop(CFRunLoopGetMain())
            }
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

    /// `--practice-sim <wav>` — the onboarding practice card's sandbox invariant, headless
    /// (asserted by regression.sh under WARBLE_HOME): run the real pipeline over a fixture WAV,
    /// then push the result through the store's record gate twice — first tagged `sandbox`
    /// (History/stats must not move), then as the control dictation (must land, so a store that's
    /// simply broken can't fake a pass). Prints the raw → cleaned transformation the card shows.
    private static func practiceSim(wav: URL) -> Never {
        Lexicon.shared.load()   // honors WARBLE_DICTIONARY, like the app
        Snippets.shared.load()  // honors WARBLE_HOME, like the app
        var outcome = Transcribers.Outcome.failed
        var done = false
        Transcribers.run(wav, clipDuration: 10) { o in
            outcome = o; done = true; CFRunLoopStop(CFRunLoopGetMain())
        }
        while !done { CFRunLoopRunInMode(.defaultMode, 120, false) }
        guard case .text(let raw) = outcome else {
            FileHandle.standardError.write(Data("\(DictateError.transcribeFailed.message)\n".utf8))
            exit(1)
        }
        let spell = SpellOut.process(raw)
        let cleaned = Snippets.shared.expand(Lexicon.shared.apply(Cleaners.best(for: spell.text).clean(spell.text)))
        print("raw: \(raw)")
        print("cleaned: \(cleaned)")
        func ctx(sandbox: Bool) -> DictationContext {
            DictationContext(durationMs: 1000, engine: Transcribers.activeEngineName(),
                             appBundleId: nil, appName: nil, secure: false, sandbox: sandbox)
        }
        let before = InsightStore.shared.events.count
        InsightStore.shared.record(cleaned, raw: raw, ctx: ctx(sandbox: true), audioSource: nil)
        let sandboxed = InsightStore.shared.events.count == before
        print(sandboxed ? "sandbox: nothing recorded" : "sandbox: LEAKED into history")
        InsightStore.shared.record(cleaned, raw: raw, ctx: ctx(sandbox: false), audioSource: nil)
        let control = InsightStore.shared.events.count == before + 1
        print(control ? "control: recorded" : "control: record failed")
        exit(sandboxed && control ? 0 : 1)
    }

    /// `--bench-e2e <wav> [N]` — per-run "run=<n> ms=<ms>" lines, then a summary
    /// ("runs= ok= clip_s= level= median_ms= p95_ms= engine=", engine last: its name has spaces)
    /// and the final paste-ready string as "text=…". Median/p95 conventions match
    /// scripts/bench/stats.ts, which aggregates the cold (one-run-per-process) mode.
    private static func benchE2E(wav: URL, runs: Int) -> Never {
        guard FileManager.default.fileExists(atPath: wav.path) else {
            FileHandle.standardError.write(Data("no such wav: \(wav.path)\n".utf8))
            exit(2)
        }
        // Clip duration from the file, so the engine timeout scales exactly as in the app.
        let clipDuration = (try? AVAudioFile(forReading: wav))
            .map { Double($0.length) / $0.processingFormat.sampleRate } ?? 10
        Lexicon.shared.load()  // honors WARBLE_DICTIONARY, like the app and --apply
        Snippets.shared.load() // honors WARBLE_HOME, like the app
        var times: [Double] = []
        var text = ""
        var failed = 0
        for n in 1...runs {
            let start = DispatchTime.now()
            var outcome = Transcribers.Outcome.failed
            var done = false
            Transcribers.run(wav, clipDuration: clipDuration) { o in
                outcome = o; done = true; CFRunLoopStop(CFRunLoopGetMain())
            }
            while !done { CFRunLoopRunInMode(.defaultMode, 120, false) }
            switch outcome {
            case .text(let raw):
                let spell = SpellOut.process(raw)
                text = Snippets.shared.expand(Lexicon.shared.apply(Cleaners.best(for: spell.text).clean(spell.text)))
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
                times.append(ms)
                print(String(format: "run=%d ms=%.1f", n, ms))
            case .silence:
                failed += 1; print("run=\(n) FAILED (nothing heard)")
            case .failed:
                failed += 1; print("run=\(n) FAILED (\(DictateError.transcribeFailed.message))")
            }
        }
        let sorted = times.sorted()
        if sorted.isEmpty {
            print("runs=\(runs) ok=0 engine=\(Transcribers.activeEngineName())")
            exit(1)
        }
        let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        let p95 = sorted[min(sorted.count - 1, Int((0.95 * Double(sorted.count)).rounded(.up)) - 1)]
        print(String(format: "runs=%d ok=%d clip_s=%.1f level=%@ median_ms=%.1f p95_ms=%.1f engine=%@",
                     runs, sorted.count, clipDuration, Cleaners.level.rawValue, median, p95,
                     Transcribers.activeEngineName()))
        print("text=\(text)")
        exit(failed == 0 ? 0 : 1)
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
