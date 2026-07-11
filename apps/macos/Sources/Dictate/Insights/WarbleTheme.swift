import SwiftUI
import Shared

/// The Insights window's palette — every value aliases the shared `Theme` (canon: brand/tokens.md),
/// kept only so existing call sites keep reading `WarbleTheme.x` unchanged.
/// One accent only — surfaces and charts differentiate by depth/opacity, never a second hue.
enum WarbleTheme {
    static let black = Theme.black.color                   // backdrop
    static let ink = Theme.ink.color                       // raised surface (cards)
    static let line = Theme.line.color                     // hairline
    static let electric = Theme.electric.color             // the accent
    static let electricBright = Theme.electricBright.color // crest (sparing)
    static let electricText = Theme.electricText.color     // AA-safe small-text tint of the accent
    static let mist = Theme.mist.color                     // secondary text
    static let textHi = Theme.textHi.color                 // primary text
    static let warn = Theme.warn.color                     // failure states only, always with a glyph
}
