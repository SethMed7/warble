import SwiftUI

/// The "Insights AI" surface: the optional, default-off, 100% on-device layer that sits ABOVE the charts
/// in the Insights tab. Three states, one electric-blue accent, content directly on the background:
///   1. master switch OFF  → a single ENABLE section explaining the (opt-in) feature + a "Turn on" button.
///   2. ON but no engine   → a plain note pointing at Setup (never a crash).
///   3. ON + engine ready  → the summary (with Regenerate / Generating…), then suggested-word rows
///                            (Accept / Dismiss), then nudges. Sections that are empty are hidden.
/// All data comes from `AIInsightsStore` (which only ever reads local stats); this view is pure UI.
struct AIInsightsView: View {
    @ObservedObject var ai: AIInsightsStore
    @ObservedObject var store: InsightStore

    var body: some View {
        // The whole feature lives in one column so it slots cleanly above the charts in InsightsView.
        VStack(alignment: .leading, spacing: 0) {
            if !store.aiInsightsEnabled {
                enableSection                       // state 1: opt-in
            } else if !ai.isAvailable {
                unavailableSection                  // state 2: enabled, no on-device engine yet
            } else {
                summarySection                      // state 3: enabled + available
                if let snap = ai.snapshot, !snap.suggestions.isEmpty {
                    Hairline().padding(.vertical, 20)
                    suggestionsSection(snap.suggestions)
                }
                if let snap = ai.snapshot, !snap.nudges.isEmpty {
                    Hairline().padding(.vertical, 20)
                    nudgesSection(snap.nudges)
                }
            }
        }
    }

    /// The one place the sparkle glyph appears — it marks the generative layer, nothing else.
    private func aiHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 12, weight: .medium)).foregroundStyle(WarbleTheme.electric)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
        }
    }

    // MARK: state 1 — enable (master switch off)

    /// The opt-in pitch. Plain about what it is and that it's off by default and stays on-device; the
    /// "Turn on" button flips the master switch and kicks the auto path so a snapshot starts building.
    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            aiHeader("Insights AI")
            Text("Optional, on-device weekly summary, suggested words, and nudges — default off, nothing leaves your Mac.")
                .font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn on") {
                store.aiInsightsEnabled = true
                ai.refreshIfNeeded()
            }
            .buttonStyle(AIPrimaryButton())
            .padding(.top, 4)
        }
    }

    // MARK: state 2 — enabled but engine not installed

    /// Enabled, but the on-device cleanup engine isn't installed — so there's no model to phrase a
    /// summary. Not a crash, not a blank; points at Setup.
    private var unavailableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            aiHeader("Insights AI")
            Text("Insights AI needs the on-device cleanup engine. Install it from Setup and your weekly summary will appear here — still 100% on your Mac.")
                .font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: state 3a — summary

    /// The generative recap: the cached summary text, a relative "Updated …" footer, and a Regenerate
    /// action. While a pass runs we swap in a "Generating…" state; if the cache is still empty (auto mode
    /// is mid-refresh on first open) we say so rather than show a blank.
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                aiHeader("This week")
                Spacer(minLength: 0)
                Button(action: { ai.regenerate() }) {
                    Label("Regenerate", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(WarbleTheme.electricText)
                .disabled(ai.isGenerating)
                .opacity(ai.isGenerating ? 0.5 : 1)
            }

            if ai.isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(WarbleTheme.electric)
                    Text("Generating…").font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                }
            } else if let snap = ai.snapshot {
                Text(snap.summary).font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Updated \(Self.relative(snap.generatedAt))")
                    .font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
            } else {
                // No cache yet and not (yet) generating — the auto path will fill this when eligible.
                Text("Your weekly recap will appear here.").font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
            }

            if let err = ai.lastError {
                Text(err).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
            }
        }
    }

    // MARK: state 3b — suggested words

    /// Deterministic suggested dictionary rules. Each row reads "from → to · reason" with Accept (learns
    /// it) and Dismiss (drops it). Rows are divided by the dashboard's inset hairlines.
    private func suggestionsSection(_ suggestions: [AISuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Suggested words")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { s in
                    suggestionRow(s)
                    if s.id != suggestions.last?.id { Hairline() }
                }
            }
        }
    }

    private func suggestionRow(_ s: AISuggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.from).font(.system(size: 13)).foregroundStyle(WarbleTheme.mist)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(WarbleTheme.mist)
                    Text(s.to).font(.system(size: 13, weight: .semibold)).foregroundStyle(WarbleTheme.textHi)
                }
                Text(s.reason).font(.system(size: 11)).foregroundStyle(WarbleTheme.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button("Accept") { ai.acceptSuggestion(s) }.buttonStyle(AIPrimaryButton())
                Button("Dismiss") { ai.dismissSuggestion(s) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(WarbleTheme.mist)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: state 3c — nudges

    /// Short computed insights: an electric bolt glyph beside plain text. Always real numbers (no model).
    private func nudgesSection(_ nudges: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Nudges")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(nudges, id: \.self) { n in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(WarbleTheme.electric)
                            .padding(.top, 3)
                        Text(n).font(.system(size: 13)).foregroundStyle(WarbleTheme.textHi)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
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
            .background(RoundedRectangle(cornerRadius: 8).fill(WarbleTheme.electric.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}
