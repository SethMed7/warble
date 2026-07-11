import AppKit
import SwiftUI

/// The single source of truth for warble's style tokens. Every value is canon from `brand/tokens.md`:
/// black + ONE electric-blue accent — the gradient ends (deep/bright) belong to identity surfaces,
/// and "is it live?" is always answered by motion, never a second hue. AppKit reads `.ns`, SwiftUI
/// reads `.color`; both come from one stored value so the two worlds can't drift apart again.
public enum Theme {
    /// One token, both UI worlds. Stored once as NSColor (the app is AppKit-hosted); the SwiftUI
    /// accessor bridges on demand. Only Theme mints tokens — derive one-off treatments at the call
    /// site with `.ns.withAlphaComponent(_:)` / `.color.opacity(_:)`, never a new literal.
    public struct Token {
        public let ns: NSColor
        public var color: Color { Color(nsColor: ns) }

        init(_ hex: UInt32, alpha: CGFloat = 1) {
            ns = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                         green: CGFloat((hex >> 8) & 0xFF) / 255,
                         blue: CGFloat(hex & 0xFF) / 255,
                         alpha: alpha)
        }

        init(ns: NSColor) { self.ns = ns }
    }

    // MARK: - Palette (brand/tokens.md — the canon; change it there first)

    /// #1E5BFF — gradient base, the foot of the V. Identity surfaces only (logo, icon, hero).
    public static let electricDeep = Token(0x1E5BFF)
    /// #2E74FF — the voice. The single in-app accent: controls, the live waveform, the read-along
    /// marker, the spinner. Wherever an accent appears, it's this.
    public static let electric = Token(0x2E74FF)
    /// #3CC6FF — gradient crest, the cyan tip of the wave. Sparing: identity surfaces and the rare
    /// chart peak, never a second UI accent.
    public static let electricBright = Token(0x3CC6FF)
    /// #161520 — ink: the black surface. Both in-app panels (the dictation pill and the read-along
    /// card) and all raised dark UI.
    public static let ink = Token(0x161520)
    /// #07080C — the deepest black: window backdrops behind ink cards.
    public static let black = Token(0x07080C)
    /// #8B8794 — mist: muted text, secondary labels. ~5.1:1 on ink — passes WCAG AA for body text.
    public static let mist = Token(0x8B8794)
    /// #2A2833 — line-dark: hairline borders on dark surfaces.
    public static let line = Token(0x2A2833)
    /// #FF9F0A — warn: the single declared exception to the one-accent law. Failure/blocked states
    /// only (8.79:1 on ink), and always paired with a glyph so color is never the only signal.
    public static let warn = Token(0xFF9F0A)

    // MARK: - Derived UI tokens (treatments built on canon, shared by the overlays and windows)

    /// #7FA8FF — electric-text: the accent's AA-safe small-text/glyph tint on dark surfaces
    /// (7.70:1 on ink). Solid electric measures 4.35:1 and fails AA at ≤13px — use this instead.
    public static let electricText = Token(0x7FA8FF)
    /// Near-white primary text on dark surfaces — softer than pure white so it doesn't glare on ink.
    public static let textHi = Token(ns: NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1))
    /// The floating pill/panel fill: canon ink, barely translucent so it sits on any desktop.
    public static let pillSurface = Token(0x161520, alpha: 0.97)
    /// Semantic alias of `line` for stroke call sites that read better as "hairline" than a color.
    public static let hairline = line
}
