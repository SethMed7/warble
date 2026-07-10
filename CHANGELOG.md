# Changelog

All notable changes to **warble** (formerly **voz**). Versions are Sparkle-published; each entry
is what a user actually gets.

## 0.2.0 — 2026-07-10 · the rename release

**voz is now warble** — *to sing with trills, the way a songbird does.* New name, new mark
(a geometric songbird whose wing is three waveform bars), same product, same privacy.

- **A real dashboard.** The Insights window grew up: a unified toolbar with the section title,
  **search + a per-app filter for History right in the toolbar**, Export where you'd expect it,
  per-section titles, hover/focus states, and first-run empty states that tell you what to try.
- **A real app.** While the dashboard is open, warble appears in the **Dock** and puts up a full
  menu bar — ⌘W closes, **⌘, opens Settings** (Data & Privacy), copy/paste works everywhere, and
  clicking the Dock icon re-opens the dashboard. Close it and warble melts back into the menu bar.
  A new setting picks the behavior: Dock icon **while the dashboard is open** (default) / always / never.
- **A shorter menu.** Mode toggles stay up top; the details now live in **Dictate ▸** and
  **Read Aloud ▸** submenus. "Insights…" is now **Open Dashboard**.
- **One design source of truth.** All colors/tokens now come from one shared Theme (canon:
  `brand/tokens.md`); several long-drifted panel colors were pulled back to spec, and the design
  law ships machine-readable in `DESIGN.md`.
- **The rename, done safely.** Your data moves itself: an existing `~/.voz` becomes `~/.warble` on
  first launch (one rename, nothing re-downloads). `VOZ_*` environment overrides still work. The
  internal bundle identifier deliberately stays `io.github.sethmed7.voz` so updates keep flowing
  and macOS permission grants survive — it's plumbing, and nothing user-visible shows it.

## 0.1.8 — 2026-07-02

- On-device performance + efficiency pass: in-process loopback HTTP for the warm engines (no more
  per-request `curl`), in-process audio conversion, history recordings stored as 16 kHz AAC
  (~25× smaller), engine warmup overlapped with speech, waveform timers that actually stop.

## 0.1.7 — 2026-06-24

- First self-updating release: **Check for Updates…** + a quiet daily check via Sparkle, every
  update verified against a pinned EdDSA key. Signed, notarized, stapled.

## 0.1.0 – 0.1.6 — June 2026

- voz is born as the blend of **leelo** (read aloud) + **dictado** (dictate): one menu-bar app,
  two capabilities, 100% on-device. Warm Parakeet ASR + Kokoro TTS servers, deterministic +
  optional MLX LLM cleanup, the learn-from-edits dictionary, the Insights stats window, native
  engine Setup with consent-first downloads, the shared `~/.memex/ai` model store, branded
  notarized DMG.
