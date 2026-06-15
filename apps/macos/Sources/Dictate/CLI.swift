import AppKit

/// Headless entries for the dictation pipeline (CI / dev smoke tests). No UI, no hotkey.
/// `--clean`, `--transcribe`, `--engine`, `--apply`, `--selftest`.
public enum DictateCLI {
    /// Returns true if it handled the args (the caller should then exit).
    public static func handle(_ args: [String]) -> Bool {
        if let i = args.firstIndex(of: "--clean"), i + 1 < args.count {
            print(BasicCleaner.cleaned(args[i + 1]))
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

    /// Verify the learn-from-edits detection logic headlessly.
    private static func runSelftest() {
        var fails = 0
        func check(_ ok: Bool, _ name: String) { print((ok ? "ok   " : "FAIL ") + name); if !ok { fails += 1 } }

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
