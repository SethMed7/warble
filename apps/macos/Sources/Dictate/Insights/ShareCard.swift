import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Shared

/// The share card (ROADMAP 0.6 dashboard — "Save a stats card"): a branded, fully local PNG of
/// three headline stats already on Home — nothing computed just for this view, nothing sent
/// anywhere. This is warble's one declared identity-surface exception (DESIGN.md): the deep→cyan
/// voice gradient, forbidden on every in-app surface, is allowed here because the card is MEANT to
/// leave the app (posted, texted, dropped in a doc) — the same rule that already lets the gradient
/// live on the logo, icon, and marketing pages, just never in-app chrome.
struct ShareCardView: View {
    let stats: ShareCardStats
    static let size = CGSize(width: 960, height: 600)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The EXACT voice gradient (brand/tokens.md: `#1E5BFF → #3CC6FF`, "the wave enters in
            // deep royal, the song crests in cyan") as a diagonal band across black — the mark's
            // own signature, not an invented variant, kept to a band (not the full card) so the
            // stat text stays on plain black at full contrast.
            LinearGradient(
                stops: [
                    .init(color: Theme.black.color, location: 0.0),
                    .init(color: Theme.black.color, location: 0.32),
                    .init(color: Theme.electricDeep.color, location: 0.48),
                    .init(color: Theme.electricBright.color, location: 0.6),
                    .init(color: Theme.black.color, location: 0.85),
                    .init(color: Theme.black.color, location: 1.0),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(nsImage: WarbleMark.coloredMark(height: 34))
                    Text("warble").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                }
                Spacer(minLength: 40)
                VStack(alignment: .leading, spacing: 22) {
                    statLine(stats.wordsLine)
                    statLine(stats.wpmLine)
                    statLine(stats.streakLine)
                }
                Spacer(minLength: 40)
                Text("the voice layer for your Mac — 100% on-device, always")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(56)
            // A light legibility shadow, not a DESIGN.md "glow" — this card can sit over its own
            // bright gradient band, unlike any in-app surface, so text needs the insurance a flat
            // ink card never does.
            .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func statLine(_ s: String) -> some View {
        Text(s).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
    }
}

/// The three headline numbers, built once from the store — never recomputed independently, so the
/// card always says exactly what Home says.
struct ShareCardStats {
    let wordsLine: String
    let wpmLine: String
    let streakLine: String
}

enum ShareCard {
    /// nil when there's nothing to share yet (no real dictation) — the caller hides the button.
    static func stats(from store: InsightStore) -> ShareCardStats? {
        guard !store.dictations.isEmpty else { return nil }
        return ShareCardStats(
            wordsLine: "\(store.totalWordsCompact) words dictated",
            wpmLine: TypingBaseline.compactHeadline(wpm: store.avgWPM) ?? "\(store.avgWPM) wpm",
            streakLine: "\(store.dayStreak)-day streak")
    }

    /// Rasterize the card to PNG @2x — the same ImageRenderer → NSBitmapImageRep plumbing as every
    /// other render seam (DictationDetailView's --render-history, SetupView's --render-setup),
    /// reused here for a REAL feature: "Save a stats card" calls this in release builds too, not
    /// just the DEBUG CLI seam that lets regression.sh prove it headlessly.
    @MainActor static func renderPNG(_ stats: ShareCardStats, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(stats: stats).environment(\.colorScheme, .dark))
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = ShareCardView.size
        return rep.representation(using: .png, properties: [:])
    }

    /// The Home button's action: render from the LIVE store and let the user pick where it lands
    /// (NSSavePanel — the same idiom as HistoryExport). Silently no-ops with nothing to share yet
    /// (the button is hidden then, so this should never actually be reached in that state); a
    /// picked destination that fails to write (read-only volume, a folder that vanished mid-panel)
    /// surfaces a plain NSAlert instead of pretending the save happened.
    @MainActor static func save(store: InsightStore) {
        guard let s = stats(from: store), let png = renderPNG(s) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "warble-stats.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't save the stats card"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
