# warble vs. Handy

*DRAFT — staged for warble's public launch, not yet linked from anywhere. See
[docs/vs/README.md](README.md) for what "draft" means here. Every Handy fact below is cited to its
GitHub repository (read directly via the GitHub API, 2026-07-12) or its own site.*

Handy is the biggest free-local rival by a wide margin — 26,337 GitHub stars, MIT-licensed, and a
release cadence that shipped v0.9.2 the same day this page cites it. If "free + local + open source"
were enough of a position on its own, Handy would already own it. This page starts there, because
it has to.

## The same-engine fact, faced head-on

Handy transcribes with **NVIDIA Parakeet** — the same family of model warble runs. Handy uses
Parakeet V3 via `transcribe-rs` (CPU-optimized, automatic language detection); warble runs the
Parakeet TDT checkpoint via `sherpa-onnx`. Different exact implementation, same core engine, and
this page isn't going to pretend otherwise. **On raw transcription, this is parity, not a warble
win.** If you strip both apps down to "records audio, runs Parakeet, types the result," there is no
honest argument that warble's engine is better — it's the same model family doing the same job.

So the case for warble here has to be made honestly, above the engine, not at it:

- **Bidirectional voice.** Handy is speech-to-text only — no read-aloud anywhere in its docs or
  repo. warble reads text back to you in the same voice, following along word by word. This is the
  single feature no dictation-only app in this whole category can copy without becoming a
  different product.
- **A learning dictionary, built in.** Handy's own README doesn't describe a native custom-word or
  learned-correction system; dictionary management currently exists only via a **third-party**
  Raycast extension, not inside Handy itself. warble learns from corrections and spoken spelling
  natively, no third-party plugin required.
- **A local dashboard with real retention mechanics** — WPM framed against typing averages,
  human-unit word counts, a streak heatmap, visible "warble learned: `<word>`" moments — all zero
  telemetry, all local. Handy doesn't ship an equivalent stats surface as of this writing.
- **Cleanup levels with a raw-transcript reveal.** None/Light/Medium/High, with "what you actually
  said" always one click away. Handy's README describes VAD filtering and model selection, not a
  tiered cleanup/polish pipeline with an undo path.

If warble ever reads as "Handy but Mac-only," the wedge is gone — this is a named risk in warble's
own roadmap, not a claim invented for this page.

## What they do better

- **Cross-platform, genuinely.** Windows, macOS, and Linux, all first-class, with a Homebrew cask
  and a winget package (community-maintained, per their README) on top of native installers.
- **Bigger, faster-moving community.** 26,337 stars vs. a solo project; releases have shipped
  same-day as this page was written. Contributions are explicitly welcomed — "the most forkable"
  speech-to-text app, by their own framing — where VoiceInk (for contrast) currently isn't accepting
  PRs at all.
- **Both push-to-talk and toggle modes**, configurable per user, plus a documented CLI for remote
  control (`--toggle-transcription`, `--cancel`, etc.) — useful for scripting that warble doesn't
  expose today.
- **Transparent about its own rough edges.** Their README lists real, open issues by name (Whisper
  crashes on some configurations, limited Wayland support) instead of hiding them — a posture worth
  respecting, not something to hold against them.

## The honest comparison table

| | Handy | warble |
| --- | --- | --- |
| License | MIT | MIT (open source at public launch) |
| Price | Free | Free, no tier, nothing to unlock |
| Offline | Yes, entirely — "This happens on your own computer without sending any information to the cloud." No cloud transcription or cloud AI path found anywhere in the repo | Yes, always — no cloud code path exists in the app at all |
| Accounts | None | None |
| Telemetry | None currently; **opt-in, privacy-first anonymous analytics is listed as "In Progress" on their own roadmap** — not yet shipped as of this writing | None, ever, no analytics on any roadmap |
| Read aloud | None — speech-to-text only | Kokoro-82M neural voices, select + ⌃V, word-by-word follow-along panel |
| Learning dictionary | Not native; dictionary management exists only via a third-party Raycast extension | Yes — learns from corrections and spoken spelling, local-only, built in |
| Latency (warm) | No independently comparable figure published; their own claim is a **throughput multiplier**, not a wall-clock time — "~5x real-time speed on mid-range hardware (tested on i5)" for Parakeet V3 CPU-only | ~65 ms median engine time (warm Parakeet), + an estimated ~20–60 ms for legs the harness can't reach — see the note below |
| WER | No published benchmark found | 0.9% WER (Parakeet) on a 40-clip synthetic corpus — see the note below |

**A note on the two warble rows:** the latency figure is warble's own paste-path harness timing
(WAV → transcription → cleanup → paste-ready string) over a fixture clip, plus an *estimated*
allowance for legs the harness can't reach (key-up handling, WAV finalize, the paste event) — not a
full release-to-text-visible measurement, and **not a like-for-like comparison to Handy's "5x
real-time" figure**, which describes processing throughput on a specific CPU, not end-to-end
latency on any machine. warble's WER figure is scored on **studio-clean synthetic speech**, a
corpus that structurally underestimates real-world error for every engine — warble's included, and
since both apps can run the same Parakeet family, a same-corpus head-to-head WER number is the
single most useful benchmark this page doesn't have yet; it's future work, not a claim made here.
Full method and reproduction commands: [docs/benchmarks.md](../benchmarks.md).

## Who should pick them

If you need Windows or Linux support, want the largest and most active open-source community in
this exact category, want to script dictation from the command line, or you specifically want to
contribute code upstream to a project that's actively accepting it — Handy is a genuinely excellent
choice, and the honest default recommendation for anyone who isn't Mac-only.

## Who should pick warble

If you're Mac-only and want that focus to buy you things a cross-platform app structurally can't
prioritize the same way — a built-in learning dictionary, a local stats dashboard, cleanup levels
with an undo path — or, again, the one verb Handy doesn't have at all: reading text back to you in
the same voice, following along word by word — warble is built for you. Just don't come here
expecting a better transcription engine than Handy's; on that specific axis, it's the same one.

## Sources

- [github.com/cjpais/Handy](https://github.com/cjpais/Handy) — README, architecture, roadmap,
  known issues, star count and release history (read via the GitHub API, 2026-07-12)
- [handy.computer](https://handy.computer) — positioning ("Free / Open Source / Private / Simple")
- [docs/benchmarks.md](../benchmarks.md) — warble's own latency/WER numbers, method, and caveats
- [ROADMAP.md](../../ROADMAP.md) — "the free-local pack erodes the wedge" / "Handy but Mac-only" as
  a named standing risk, not a claim invented for this page
