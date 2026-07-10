---
name: warble
description: The voice layer for your Mac — one electric-blue signal on black, 100% on-device.
colors:
  electric-deep: "#1E5BFF"
  electric: "#2E74FF"
  electric-bright: "#3CC6FF"
  electric-text: "#7FA8FF"
  black: "#07080C"
  ink: "#161520"
  line: "#2A2833"
  mist: "#8B8794"
  text-hi: "#EDF0F5"
  warn: "#FF9F0A"
typography:
  display:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "32px"
    fontWeight: 700
    lineHeight: 1.1
  headline:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.15
  title:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.45
  reader:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: 1.3
  data-label:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 600
    letterSpacing: "0.6px"
rounded:
  xs: "6px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
  page: "28px"
components:
  button-primary:
    backgroundColor: "{colors.electric-deep}"
    textColor: "#FFFFFF"
    rounded: "{rounded.sm}"
    padding: "7px 16px"
  button-primary-hover:
    backgroundColor: "{colors.electric}"
  button-primary-pressed:
    backgroundColor: "#1E5BFFB3"
  button-ghost:
    backgroundColor: "#00000000"
    textColor: "{colors.mist}"
    rounded: "{rounded.sm}"
    padding: "7px 12px"
  button-ghost-hover:
    textColor: "{colors.text-hi}"
  control-circle-primary:
    backgroundColor: "{colors.electric}"
    textColor: "#FFFFFF"
    rounded: "{rounded.pill}"
    size: "34px"
  control-circle-neutral:
    backgroundColor: "{colors.line}"
    textColor: "{colors.text-hi}"
    rounded: "{rounded.pill}"
    size: "32px"
  card:
    backgroundColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "16px"
  stat-card:
    backgroundColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "20px"
  overlay-pill:
    backgroundColor: "#161520F7"
    rounded: "{rounded.pill}"
  chip:
    backgroundColor: "#2A283380"
    textColor: "{colors.mist}"
    rounded: "{rounded.xs}"
    padding: "1px 6px"
  sidebar-row:
    backgroundColor: "#00000000"
    textColor: "{colors.mist}"
    rounded: "{rounded.sm}"
    padding: "7px 10px"
  sidebar-row-selected:
    backgroundColor: "#2E74FF2E"
    textColor: "{colors.text-hi}"
    rounded: "{rounded.sm}"
    padding: "7px 10px"
---

<!-- Generated from brand/tokens.md. brand/tokens.md is the canon and stays the canon; it wins on
     ANY conflict. This DESIGN.md is its machine-readable DISTILLATION for agent consumption, not
     a second brand book. REGENERATE it (never hand-edit) when brand/tokens.md changes. In-app
     colors resolve through apps/macos/Sources/Shared/Theme.swift — code references tokens, never
     raw hex. Derived values documented here: text-hi #EDF0F5 is the app's high-emphasis text
     (long defined in code as (0.93, 0.94, 0.96)); electric-text #7FA8FF is the AA-safe text/glyph
     tint of electric (7.70:1 on ink); warn #FF9F0A (macOS systemOrange, dark) is the single
     declared exception to the one-accent law, failure states only. -->

# Design System: warble

## 1. Overview

**Creative North Star: "One lit signal on black."**

warble is a quiet black instrument, and the only living thing on it is the voice — a single
electric-blue signal that moves when you speak and rests when you don't. Every surface is dark
(black `#07080C` backdrop, ink `#161520` panels), every border is a hairline, and every trace of
blue means either *warble itself* or *the user acting*. The system deliberately rejects: second
accent hues, light in-app surfaces, decorative glow, gradient washes (the deep→cyan voice gradient
belongs to the logo, icon, and marketing — never in-app chrome), and "AI-powered" hype styling.
The tone is calm, plain, and honest about privacy — lowercase, unhurried, bragging about what
*doesn't* happen (no cloud, no accounts, no saved audio).

Density is utility-grade: a menu-bar tool with small floating capsules and one real dashboard
window. Layout breathes on a 4px grid (page gutters 20–28px, card innards 16px); motion is
restrained — entrances fire once (the pill's 180ms fade-up), and the only *looping* motion in the
whole app is the honest live signal: the waveform reacting to your voice and the spinner spinning
while it processes. Nothing else moves at rest.

**Key Characteristics:**
- Two dark surfaces only (black backdrop, ink panels) separated by hairlines — no third tone.
- One accent, electric blue, spent where the user acts or where warble is alive.
- Motion — not a second color — is the "live" signal.
- SF Pro everywhere in-app; the brand faces (Sora, Inter) never appear inside the app.
- Floating surfaces are full capsules; windowed surfaces are soft rectangles (6–16px).

## 2. Colors

A two-color brand: electric blue on black — the blue is the voice, the black is the surface it
lives on.

### Primary
- **Electric** (`#2E74FF`): the voice. The one in-app accent — filled primary controls (glyph-only),
  the live waveform bars, the spinner, the read-along word marker, progress bars, selection tints.
  As a *fill* behind white glyphs (4.15:1 ≥ 3:1 UI floor) and as *large/heavy* marker text it is
  compliant; as small text it is not — use electric-text.
- **Electric Deep** (`#1E5BFF`): the gradient base, "the foot of the V." In-app: the fill of
  filled *text* buttons (white label = 5.26:1, passes AA body). Hover lightens it to electric.
- **Electric Bright** (`#3CC6FF`): the gradient crest — sparing. In-app it appears in exactly one
  role: the keyboard-focus ring (9.22:1 on ink; visible even against electric fills).
- **Electric Text** (`#7FA8FF`): the accent's small-text/glyph form on dark surfaces — 7.70:1 on
  ink, 8.53:1 on black. Use for accent-colored labels ≤13px ("⌘V to paste", "Undo", "● watching").

### Neutral
- **Black** (`#07080C`): the backdrop — window and detail-pane background, the deepest layer.
- **Ink** (`#161520`): every raised dark surface — the dictation pill, the read-along panel, the
  learn capsule, cards, and the sidebar. Floating overlays use it at 97% alpha (`#161520F7`).
- **Line** (`#2A2833`): hairline borders on dark surfaces (1px, decorative — the glyph/label
  carries the affordance), and the fill of neutral circle controls.
- **Mist** (`#8B8794`): secondary text and labels — 5.15:1 on ink, 5.71:1 on black (AA body pass).
- **Text Hi** (`#EDF0F5`): high-emphasis text — 15.8:1 on ink. Never name a light color "ink."

### State
- **Warn** (`#FF9F0A`): the single declared exception to the one-accent law — failure/blocked
  states only (8.79:1 on ink), and always paired with a glyph so color is never the only signal.
  Success is **never a color**: it's a checkmark glyph (electric) beside text-hi text.

### Named Rules
**The One-Accent Rule.** Electric is the only hue in the app. Its tints (electric-deep fills,
electric-text labels, 14–18% washes) are the *same* accent, not new colors. Accent is spent only
where the user acts or where warble is alive — never on decorative borders, random headings, or every
icon in a list. The sole non-blue chroma permitted is warn, on failures, with a glyph.

**The Motion-Is-The-Signal Rule.** "Is it listening / is it reading?" is answered by motion, never
by a second hue: the waveform only moves while the mic is hot or audio is playing; the spinner only
spins while processing. Never add a "recording red," a "live green," or a pulsing tint — and never
let the waveform animate while idle. This is the single most important honesty in a voice tool.

**The Dark-Card Rule.** Both in-app panels — the dictation pill and the read-along panel — are the
same black card: ink `#161520`, hairline `#2A2833`, one electric accent. All in-app surfaces are
dark; paper `#F5F2EC` and line-light exist only for marketing/docs and are forbidden in-app. Never
introduce ad-hoc darks (`#161616`, `#1C1C1E` are known past drift — extinct, do not resurrect).

## 3. Typography

**Display Font:** SF Pro (system) — in-app, always.
**Body Font:** SF Pro (system).
**Marketing faces:** Sora (display/wordmark) and Inter (web/docs body) never appear inside the app.

**Character:** native, quiet, unhurried. The app reads like a well-set macOS utility, not a
marketing surface. Weights carry hierarchy: `.heavy` is reserved for the read-along word marker,
`.bold`/`.semibold` for controls and values, `.medium`/`.regular` for status and body.

### Hierarchy
- **Display** (700, 32px, 1.1): stat values on dashboard cards. Large text — 3:1 floor applies.
- **Headline** (700, 24px, 1.15): window/page titles ("Welcome to warble", "Better engines").
- **Title** (600, 15px, 1.3): card and row titles (engine names, gesture titles).
- **Reader** (400, 15px, 1.5): the read-along transcript. Inactive segments mist, active segment
  text-hi, and the live word: 15px **heavy** white on electric (4.15:1 — passes as large text,
  ≥ 18.66 CSS px at ≥700 weight).
- **Body** (400, 13px, 1.45): descriptions, list content, button labels (600 in buttons).
- **Label** (500, 11px, 1.3): status lines, timestamps, meta counts — mist, on ink/black only.
- **Data-label** (600, 10px, +0.6px tracking, UPPERCASE): true data labels only ("YOUR MAC").

### Named Rules
**The Data-Label Rule.** Uppercase micro-labels are data labels (spec chips, table headers) —
never section eyebrows. Default eyebrow count per screen: zero.

**The Lowercase Rule.** In running text the product is always lowercase **warble** (later: the
renamed wordmark follows the same law). Never "AI-powered"; always "on-device."

## 4. Elevation

warble is flat and tonal: depth comes from exactly two surface tones — black backdrop below, ink
panels above — separated by 1px `line` hairlines, not from shadow stacks. Hairlines are
decorative (the label/glyph carries the affordance), so they are exempt from the 3:1 non-text
floor by design.

### Shadow Vocabulary
- **Floating panel** (system `NSWindow` shadow, `hasShadow = true`): the read-along panel, the
  dictation pill, and the learn capsule float above other apps' content — the OS shadow is the
  only thing separating them from an unknown wallpaper. Always on for floating overlays.
- **Callout** (`box-shadow: 0 10px 24px rgba(0,0,0,0.5)`): the tutorial coachmark card — the one
  in-window shadow, earned because the card floats above a dimmed layer.
- **Lit signal** (`0 0 4px rgba(46,116,255,0.7)` glow on waveform bars): see rule below.

### Named Rules
**The Lit-Signal Rule.** The waveform bars (and only the waveform bars) glow — a 4px electric
halo that makes the voice read as *lit*, matching the app icon. That is the entire glow budget of
the application. No other element glows, blooms, or casts colored light. If a glow can't say "this
is the voice," delete it.

**The Two-Tone Rule.** If a design needs a third dark surface tone, it's wrong — restructure with
spacing and hairlines instead. Raised = ink. Backdrop = black. That's the whole elevation system.

## 5. Components

### Buttons
- **Shape:** softly rounded (8px); text buttons are compact (7px × 16px padding, 13px semibold).
- **Primary (filled text button):** white on electric-deep `#1E5BFF` (5.26:1). Hover lifts the
  fill to electric `#2E74FF`; pressed drops fill opacity to 70%.
- **Ghost:** mist label, no fill; hover brightens the label to text-hi.
- **Focus:** every focusable control shows a 2px electric-bright `#3CC6FF` ring at 2px offset —
  the one in-app appearance of the crest color. Never suppress it; color-shift alone is not focus.

### Circle Controls (the overlay control idiom)
- **Primary** (34–36px circle): electric fill, white glyph (13px semibold SF Symbol) — the single
  primary act of a surface: play/pause, accept (✓).
- **Neutral** (30–32px circle): `line` fill, text-hi glyph (12.7:1) — every secondary act: stop,
  minimize/expand, voice picker, dismiss (✕). One electric circle per surface; the rest neutral.
- **Hover:** fill lightens ~8% (white 8% overlay); **pressed:** fill darkens ~10%. Overlays are
  non-activating panels (keyboard focus never enters them), so hover/pressed is their state story.

### Cards / Containers
- **Corner Style:** md (12px) for in-page cards; lg (16px) for hero stat cards and window-level
  panels; xs (6px) for chips.
- **Background:** ink, always; **Border:** 1px `line` hairline; **Shadow:** none (Two-Tone Rule).
- **Internal Padding:** 16px (stat cards 20px).
- A card must earn its border — group genuinely separable content; prefer hairlines and spacing
  over boxes-in-boxes. Disabled cards drop to 50% opacity (exempt from contrast floors).

### Capsule Pills (floating overlays)
- **Shape:** full capsule (radius = height/2); **Surface:** ink at 97% (`#161520F7`) with a 1px
  `line` border; positioned bottom-center of the active screen, +28px.
- **The Capsule Rule.** Elements inside a capsule sit concentric with its round ends: edge inset
  = (capsuleHeight − elementDiameter) / 2. Odd-looking insets (7px, 9px) that satisfy this formula
  are correct; insets that don't are drift.

### Chips
- **Style:** `line` at 50% over ink, mist 11px text (4.68:1), xs radius, 1px × 6px padding. Data
  chips only (sizes, counts) — not interactive.

### Sidebar Rows (dashboard)
- **Default:** mist label + glyph on ink, sm radius, 7px × 10px padding; hover: subtle wash
  (white 4% or line 50%). **Selected:** electric 18% wash + text-hi semibold. Selection is wash +
  weight, not accent text.

### The Waveform (signature)
A row of rounded electric bars with the lit-signal glow: the dictation pill's bars react to the
live mic (VU-style), the mini player's ripple while audio plays; both rest flat when idle. Colors
come from tokens (bars: electric); **the animation timing is behavioral code, not styling — do
not retune it from this document.** The spinner is a 2px electric arc, 16px, only while processing.

## 6. Do's and Don'ts

### Do:
- **Do** measure contrast, not vibe it: body text ≥ 4.5:1, large/UI ≥ 3:1. Reference pairs:
  mist/ink 5.15:1 · text-hi/ink 15.8:1 · electric-text/ink 7.70:1 · white/electric-deep 5.26:1.
- **Do** use electric-text `#7FA8FF` for any accent-colored text at ≤13px on dark surfaces.
- **Do** keep one electric circle per overlay — the primary act — and make every other control
  neutral (`line` fill, text-hi glyph).
- **Do** show keyboard focus (2px electric-bright ring) on every focusable control in windowed
  UI, and hover/pressed feedback on every control in the non-activating overlays.
- **Do** keep floating pills full capsules with concentric insets, on ink `#161520F7`, hairline
  `line`, bottom-center +28px of the screen under the pointer.
- **Do** hold the 4px spacing grid (4/8/12/16/20/24/28) and the radius scale (6/8/12/16/capsule).
- **Do** signal success with a checkmark glyph + text-hi label, and failures with warn + a glyph.

### Don't:
- **Don't** resurrect the ad-hoc darks — `#161616`, `#1C1C1E`, `#36383D`, `#3D4045`, `#45474C`
  are extinct drift; the only dark surfaces are black, ink, and line.
- **Don't** set solid electric `#2E74FF` as small text on ink/black — it measures 4.35:1 and
  fails AA. That's what electric-text is for.
- **Don't** introduce a second hue: no success green, no recording red, no purple gradients, no
  neon accents, no glassmorphism. Motion is the live signal (Motion-Is-The-Signal Rule).
- **Don't** add glows or shadows beyond the three in the vocabulary — no smudge glows, no
  unmotivated shadows; light needs a source (Lit-Signal Rule).
- **Don't** overuse cards or eyebrows: no boxes-in-boxes, no caps section labels — uppercase
  micro-type is for data labels only (Data-Label Rule).
- **Don't** name a light color "ink" — ink is the dark surface; light text is text-hi.
- **Don't** use the voice gradient (deep→cyan) inside the app — it belongs to the logo, icon, and
  marketing surfaces only.
- **Don't** bring Sora or Inter into the app; in-app type is SF Pro, and "warble" stays lowercase in
  prose. Never "AI-powered"; always "on-device."
- **Don't** let anything loop at rest: waveforms flat when idle, spinners gone when done,
  transition debris dissolved.
