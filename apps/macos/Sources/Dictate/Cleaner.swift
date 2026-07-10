import Foundation

/// Cleanup engines are pluggable so a local-LLM cleaner (e.g. the warm MLX server)
/// can slot in — any engine must stay on-device; see README.
protocol Cleaner {
    func clean(_ raw: String) -> String
}

/// The deterministic cleaner: the built-in Swift twin of core/clean.ts. The app runs this port
/// directly rather than spawning bun over a deployed ~/.warble/clean.ts — the rules ship with the
/// binary (an app update can't be shadowed by a stale helper from an older setup), and each
/// dictation saves a process spawn. core/clean.ts stays the canonical, acceptance-tested source;
/// the twins are kept rule-identical.
struct BasicSwiftCleaner: Cleaner {
    func clean(_ raw: String) -> String { BasicCleaner.cleaned(raw) }
}

enum Cleaners {
    /// The on-device "polish with AI" toggle. On by default, but it only does
    /// anything once an open-weight model is installed (scripts/setup-cleaner.sh);
    /// until then `best()` returns the deterministic cleaner regardless.
    static var llmEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "llmCleanupEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "llmCleanupEnabled") }
    }

    /// Best available cleaner. With the AI layer on, the on-device LLM polishes the
    /// text (always wrapping the deterministic cleaner as its fallback): warble's own
    /// warm MLX server (Apple Silicon) is preferred, else a self-contained llama.cpp
    /// model (Intel/legacy). Otherwise the deterministic Swift twin.
    ///
    /// NOTE: probes the network/disk, so call OFF the main thread.
    static func best() -> Cleaner { select(useLLM: llmEnabled) }

    /// Like `best()`, but skips the LLM entirely when `raw` is already clean — saving the polish
    /// latency on dictations that don't need it. Use this on the live paste path.
    static func best(for raw: String) -> Cleaner { select(useLLM: llmEnabled && LLMPolish.worthRunning(raw)) }

    private static func select(useLLM: Bool) -> Cleaner {
        let base: Cleaner = BasicSwiftCleaner()
        guard useLLM else { return base }
        if MLXCleaner.isAvailable() { return MLXCleaner(fallback: base) }  // warble's own warm MLX server (Apple Silicon)
        if LLMCleaner.isAvailable() { return LLMCleaner(fallback: base) }  // self-contained llama.cpp (Intel/legacy)
        return base
    }
}
