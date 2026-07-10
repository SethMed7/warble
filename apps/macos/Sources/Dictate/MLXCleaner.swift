import Foundation

/// Preferred polish backend: a small on-device instruct model (Qwen2.5-1.5B-Instruct, Apache-2.0) run
/// via MLX — Apple's Metal array framework — kept warm in warble's OWN loopback server (WarmLLM). No
/// Ollama, no separate app to install: warble provisions the venv + model itself (scripts/setup-cleaner.sh),
/// downloads the weights with your consent, and PINS the model so cleanup is identical for everyone
/// (not "whatever model your Ollama happened to list first"). 100% on-device; the server is spawned
/// offline so transcript text can never leave the machine.
///
/// Pluggable + guarded: any failure (server down, or output that changed your words) falls back to the
/// deterministic cleaner. Same shape as WarmSherpaTranscriber wrapping WarmASR.
final class MLXCleaner: Cleaner {
    private let fallback: Cleaner
    init(fallback: Cleaner) { self.fallback = fallback }

    /// Available once the warm MLX server is installed (venv + script + a consented model download).
    static func isAvailable() -> Bool { WarmLLM.isInstalled() }

    /// Blocks on the local server — call OFF the main thread (DictateController does, on a utility queue).
    func clean(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback.clean(raw) }
        // Warm answers in well under a second; scale modestly with length and keep a sane floor (not 30s).
        let secs = max(12, Double(trimmed.count) / 12 + 8)
        guard let content = WarmLLM.shared.clean(system: LLMPolish.systemPrompt, text: trimmed, timeout: secs) else {
            return fallback.clean(raw)
        }
        let out = LLMPolish.clip(content)
        return LLMPolish.accept(out, against: trimmed) ? out : fallback.clean(raw)
    }
}
