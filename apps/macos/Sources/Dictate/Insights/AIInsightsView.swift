import SwiftUI

/// The "Insights AI" surface: the optional, default-off, 100% on-device layer that sits ABOVE the charts
/// in the Insights tab. Three states, one electric-blue accent, voz's dark cards (`.cardStyle()`):
///   1. master switch OFF  → a single ENABLE card explaining the (opt-in) feature + a "Turn on" button.
///   2. ON but no engine   → a ComingSoon-styled note pointing at Setup (never a crash).
///   3. ON + engine ready  → a summary card (with Regenerate / Generating…), then suggested-word rows
///                            (Accept / Dismiss), then nudge chips. Sections that are empty are hidden.
/// All data comes from `AIInsightsStore` (which only ever reads local stats); this view is pure UI.
struct AIInsightsView: View {
    @ObservedObject var ai: AIInsightsStore
    @ObservedObject var store: InsightStore

    var body: some View {
        // The whole feature lives in one column so it slots cleanly above `wordsCard` in InsightsView.
        VStack(alignment: .leading, spacing: 12) {
            if !store.aiInsightsEnabled {
                enableCard                          // state 1: opt-in
            } else if !ai.isAvailable {
                unavailableCard                     // state 2: enabled, no on-device engine yet
            } else {
                summaryCard                         // state 3: enabled + available
                if let snap = ai.snapshot, !snap.suggestions.isEmpty { suggestionsCard(snap.suggestions) }
                if let snap = ai.snapshot, !snap.nudges.isEmpty { nudgesCard(snap.nudges) }
            }
        }
    }

    // MARK: state 1 — enable (master switch off)

    /// The opt-in card. Plain about what it is and that it's off by default and stays on-device; the
    /// "Turn on" button flips the master switch and kicks the auto path so a snapshot starts building.
    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 16, weight: .medium)).foregroundStyle(VozTheme.electric)
                Text("Insights AI").font(.system(size: 15, weight: .semibold)).foregroundStyle(VozTheme.textHi)
            }
            Text("Optional, on-device weekly summary, suggested words, and nudges — default off, nothing leaves your Mac.")
                .font(.system(size: 12.5)).foregroundStyle(VozTheme.mist)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn on") {
                store.aiInsightsEnabled = true
                ai.refreshIfNeeded()
            }
            .buttonStyle(AIPrimaryButton())
        }
        .cardStyle()
    }

    // MARK: state 2 — enabled but engine not installed

    /// Enabled, but the on-device cleanup engine isn't installed — so there's no model to phrase a
    /// summary. Styled like the rest of the cards (not a crash, not a blank); points at Setup.
    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 16, weight: .medium)).foregroundStyle(VozTheme.electric)
                Text("Insights AI").font(.system(size: 15, weight: .semibold)).foregroundStyle(VozTheme.textHi)
            }
            Text("Insights AI needs the on-device cleanup engine. Install it from Setup and your weekly summary will appear here — still 100% on your Mac.")
                .font(.system(size: 12.5)).foregroundStyle(VozTheme.mist)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    // MARK: state 3a — summary

    /// The generative recap: the cached summary text, a relative "Updated …" footer, and a Regenerate
    /// button. While a pass runs we swap in a "Generating…" state; if the cache is still empty (auto mode
    /// is mid-refresh on first open) we say so rather than show a blank card.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 16, weight: .medium)).foregroundStyle(VozTheme.electric)
                Text("This week").font(.system(size: 15, weight: .semibold)).foregroundStyle(VozTheme.textHi)
                Spacer()
                Button(action: { ai.regenerate() }) {
                    Label("Regenerate", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(VozTheme.electricText)
                .disabled(ai.isGenerating)
                .opacity(ai.isGenerating ? 0.5 : 1)
            }

            if ai.isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(VozTheme.electric)
                    Text("Generating…").font(.system(size: 13)).foregroundStyle(VozTheme.mist)
                }
            } else if let snap = ai.snapshot {
                Text(snap.summary).font(.system(size: 13)).foregroundStyle(VozTheme.textHi)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Updated \(Self.relative(snap.generatedAt))")
                    .font(.system(size: 11)).foregroundStyle(VozTheme.mist)
            } else {
                // No cache yet and not (yet) generating — the auto path will fill this when eligible.
                Text("Your weekly recap will appear here.").font(.system(size: 13)).foregroundStyle(VozTheme.mist)
            }

            if let err = ai.lastError {
                Text(err).font(.system(size: 11)).foregroundStyle(VozTheme.mist.opacity(0.8))
            }
        }
        .cardStyle()
    }

    // MARK: state 3b — suggested words

    /// Deterministic suggested dictionary rules. Each row reads "from → to · reason" with Accept (learns
    /// it) and Dismiss (drops it). Rows are divided by the same hairline as Data & Privacy.
    private func suggestionsCard(_ suggestions: [AISuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested words").font(.system(size: 15, weight: .semibold)).foregroundStyle(VozTheme.textHi)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { s in
                    suggestionRow(s)
                    if s.id != suggestions.last?.id { Divider().overlay(VozTheme.line).padding(.vertical, 10) }
                }
            }
        }
        .cardStyle()
    }

    private func suggestionRow(_ s: AISuggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.from).font(.system(size: 13)).foregroundStyle(VozTheme.mist)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(VozTheme.mist)
                    Text(s.to).font(.system(size: 13, weight: .semibold)).foregroundStyle(VozTheme.textHi)
                }
                Text(s.reason).font(.system(size: 11)).foregroundStyle(VozTheme.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button("Accept") { ai.acceptSuggestion(s) }.buttonStyle(AIPrimaryButton())
                Button("Dismiss") { ai.dismissSuggestion(s) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(VozTheme.mist)
            }
        }
    }

    // MARK: state 3c — nudges

    /// Short computed insights, shown as quiet electric-tinted chips. Always real numbers (no model).
    private func nudgesCard(_ nudges: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nudges").font(.system(size: 15, weight: .semibold)).foregroundStyle(VozTheme.textHi)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(nudges, id: \.self) { n in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(VozTheme.electric)
                            .padding(.top, 3)
                        Text(n).font(.system(size: 13)).foregroundStyle(VozTheme.textHi)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VozTheme.electric.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .cardStyle()
    }

    // MARK: helpers

    /// A short relative phrase ("2 days ago") for the summary footer, from a Unix-epoch timestamp.
    private static func relative(_ epoch: Double) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: Date(timeIntervalSince1970: epoch), relativeTo: Date())
    }
}

/// The compact filled electric button used for the primary actions here (Turn on / Accept) — matches the
/// tutorial's accent button, scaled down for inline use. One accent only.
private struct AIPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(VozTheme.electric.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}
