# warble — brand identity

A **fresh identity**, deliberately unrelated to the two parents (leelo's coral-on-cream,
dictado's dusk-blue-on-black). warble is the voice layer for your Mac, so the system is built
around two colors: **electric blue on black.** Blue is the voice — shiny, electric, a tech
signal; black is the surface it lives on.

The mark is **the waveform as a songbird** — twelve vertical sound bars whose envelope traces a
bird in profile: tail, round body, a sharp neck step, crown, lifted beak. Read small, it's a living
waveform; read large, the bird appears. It runs on a **deep-royal → cyan gradient** (the tail sits
in deep royal; the song crests in cyan toward the beak). Canonical art: `brand/warble-mark.svg`
(color) and `apps/macos/Sources/Shared/Resources/warble_glyph.svg` (monochrome) — both **generated
by `brand/source/gen_bird_bars.py`** (tune the envelope keypoints there; never hand-edit the bars).

<img src="warble-mark.svg" alt="warble mark — a songbird built from waveform bars" width="220">

## Wordmark

`warble` — **lowercase in prose.** English: *to sing with trills, the way a songbird does* — one
word for both directions (you speak to it, it sings back). In running text and copy it's always
lowercase **warble**. Formerly **voz** (through 0.1.8); descends from the same parents, *léelo*
(read it) + *dictado* (dictation).

## Palette

| Token | Hex | Role |
| --- | --- | --- |
| **electric-deep** | `#1E5BFF` | Gradient base — the bird's tail (deep royal blue) |
| **electric** | `#2E74FF` | The voice — core electric blue: the wordmark chrome, controls, the live waveform, the read-along marker, the spinner + loading bar. The single in-app accent |
| **electric-bright** | `#3CC6FF` | Gradient crest — the cyan toward the beak, where the song comes out |
| **voice gradient** | `#1E5BFF → #3CC6FF` | The mark's signature: the song rising tail-to-beak. Identity surfaces only — logo, icon, hero, marketing |
| **ink** | `#161520` | Black surface — both in-app panels (the dictation pill **and** the read-along panel) and all dark UI |
| **black** | `#07080C` | Backdrop — the deepest black behind the mark |
| **paper** | `#F5F2EC` | Light surface — marketing / docs only; the in-app panels are dark |
| **mist** | `#8B8794` | Muted text, secondary labels |
| **line-dark** | `#2A2833` | Hairline borders on dark surfaces |
| **line-light** | `#E5E0D6` | Hairline borders on light surfaces |

### Semantics (one accent: black + blue)

- The **voice gradient** (deep → cyan) is the identity signature — it lives on the logo, the
  app icon, and marketing surfaces, where the bird *sings* the wave.
- Inside the app, a single **solid electric** (`#2E74FF`, the gradient's mid-tone) carries
  everything — identity *and* activity. It's warble wherever an accent appears: brand chrome,
  controls, and the live signal.
- "Is it listening?" stays unambiguous through **motion**, not a second hue: the waveform only
  reacts to your voice while the mic is hot, and the spinner only spins while processing — the
  single most important honesty in a voice tool.
- **Both in-app panels are dark** (`ink #161520`): the read-along panel and the dictation pill are
  the same black card with the one electric-blue accent, so the two capabilities read as one app.
  The **menu-bar icon is the songbird mark** (`apps/macos/Sources/Shared/WarbleMark.swift`, loading
  `warble_glyph.svg`), drawn as a template so it tints to the light/dark menu bar — at 18 pt the
  bird reads as a compact waveform, which is exactly right for a voice tool.

## Typography

- **Display / wordmark — Sora.** A geometric techno sans (circular *O*, even monoline, generous
  tracking), set lowercase — **warble** — beside the songbird mark. Used for the wordmark and
  large marketing display. (Wordmark SVG regeneration is pending post-rename.)
- **Body / web & docs — Inter.** Clean, technical, neutral; the natural reading face under Sora.
- **Native app — SF Pro (system).** warble is a menu-bar utility, not a marketing surface, so the
  app UI uses the system font. Weights: `.heavy` for the read-along marker, `.bold` for controls,
  `.medium`/`.regular` for status and body.

## Voice & tone

Calm, plain, honest about privacy. Lowercase, unhurried. Never "AI-powered"; always
"on-device." The product brags about what *doesn't* happen (no cloud, no accounts, no saved
audio) as much as what does.

## Tagline

> the voice layer for your Mac — speak to type, select to hear. 100% on-device.
