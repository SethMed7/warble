import Foundation

/// Cleanup engines are pluggable so a local-LLM cleaner (e.g. the warm MLX server)
/// can slot in — any engine must stay on-device; see README.
protocol Cleaner {
    func clean(_ raw: String) -> String
}

/// Level None: verbatim passthrough. Only whitespace-safe normalization (trim the ends) —
/// every word, every "um", stays exactly as transcribed.
struct PassthroughCleaner: Cleaner {
    func clean(_ raw: String) -> String { raw.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The deterministic cleaner: the built-in Swift twin of core/clean.ts. The app runs this port
/// directly rather than spawning bun over a deployed ~/.warble/clean.ts — the rules ship with the
/// binary (an app update can't be shadowed by a stale helper from an older setup), and each
/// dictation saves a process spawn. core/clean.ts stays the canonical, acceptance-tested source;
/// the twins are kept rule-identical.
struct BasicSwiftCleaner: Cleaner {
    /// The captured app category (context awareness's apply half, ROADMAP 0.6) — nil (the
    /// default, and always the case with the toggle off) is byte-identical to the pre-0.6 pass.
    var category: AppCategory? = nil
    func clean(_ raw: String) -> String { BasicCleaner.cleaned(raw, category: category) }
}

/// How much rewriting stands between the raw transcript and the paste (ROADMAP 0.3). The default
/// is verbatim-leaning (product.md §4: the words are the user's; polish is opt-in and undoable).
enum CleanupLevel: String, CaseIterable {
    case none    // verbatim passthrough — whitespace trim only
    case light   // deterministic cleanup (the core/clean.ts twin) — the default
    case medium  // deterministic + guarded LLM punctuation/filler polish (the old "Polish with AI")
    case high    // guarded LLM polish with fuller latitude (contextual fillers, structure)

    var usesLLM: Bool { self == .medium || self == .high }

    /// Menu row title: the level plus what it buys, in the menu's existing "name — detail" idiom.
    var menuTitle: String {
        switch self {
        case .none:   return "None — verbatim, exactly as heard"
        case .light:  return "Light — tidy fillers & stumbles"
        case .medium: return "Medium — punctuation & fillers (on-device AI)"
        case .high:   return "High — fuller formatting (on-device AI)"
        }
    }
}

enum Cleaners {
    /// The persisted cleanup level. Defaults to Light; a pre-0.3 "Polish with AI" toggle the user
    /// explicitly set migrates so nobody's choice is silently changed (on → Medium, off → Light).
    static var level: CleanupLevel {
        get {
            let d = UserDefaults.standard
            if let raw = d.string(forKey: "cleanupLevel"), let l = CleanupLevel(rawValue: raw) { return l }
            if let old = d.object(forKey: "llmCleanupEnabled") as? Bool { return old ? .medium : .light }
            return .light
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "cleanupLevel") }
    }

    /// Is an on-device polish model installed? WARBLE_DISABLE_LLM=1 hides it so the regression
    /// gate behaves identically with and without the premium engines present.
    static var llmAvailable: Bool {
        guard ProcessInfo.processInfo.environment["WARBLE_DISABLE_LLM"] != "1" else { return false }
        return MLXCleaner.isAvailable() || LLMCleaner.isAvailable()
    }

    /// The cleaner for the persisted level, tuned to `raw` — use this on the live paste path.
    /// `category` is context awareness's captured app category (ROADMAP 0.6, opt-in): nil — the
    /// default, and always the case with the toggle off — is byte-identical to today.
    /// NOTE: the LLM levels probe the network/disk, so call OFF the main thread.
    static func best(for raw: String, category: AppCategory? = nil) -> Cleaner {
        cleaner(at: level, for: raw, category: category)
    }

    /// The cleaner for a level. Medium skips the LLM when `raw` is already clean (saving the
    /// polish latency on dictations that don't need it); High always runs it — fuller latitude is
    /// the point of picking High. Both stay guarded (LLMPolish.accept) and fall back to the
    /// deterministic cleaner on any failure; without an installed model they ARE the deterministic
    /// cleaner. Pass `raw: nil` to skip the worth-running probe. A captured `category` shapes the
    /// deterministic pass (BasicCleaner's tone rules) and becomes one hint line in the polish
    /// prompt (LLMPolish.prompt) — None stays a pure passthrough regardless: verbatim is verbatim
    /// (product.md §4.4).
    static func cleaner(at level: CleanupLevel, for raw: String?, category: AppCategory? = nil) -> Cleaner {
        let base: Cleaner = BasicSwiftCleaner(category: category)
        switch level {
        case .none:  return PassthroughCleaner()
        case .light: return base
        case .medium:
            guard llmAvailable, raw.map(LLMPolish.worthRunning) ?? true else { return base }
            return llmCleaner(prompt: LLMPolish.prompt(LLMPolish.systemPrompt, category: category),
                              fallback: base) ?? base
        case .high:
            guard llmAvailable else { return base }
            return llmCleaner(prompt: LLMPolish.prompt(LLMPolish.systemPromptHigh, category: category),
                              fallback: base) ?? base
        }
    }

    /// Best available LLM backend: warble's own warm MLX server (Apple Silicon) is preferred,
    /// else the self-contained llama.cpp model (Intel/legacy).
    private static func llmCleaner(prompt: String, fallback: Cleaner) -> Cleaner? {
        if MLXCleaner.isAvailable() { return MLXCleaner(fallback: fallback, prompt: prompt) }
        if LLMCleaner.isAvailable() { return LLMCleaner(fallback: fallback, prompt: prompt) }
        return nil
    }
}
