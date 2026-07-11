# warble benchmarks — honest numbers, measured

*Every public performance claim warble makes traces to this file: the method, the caveats, the
reproduction command, and the actual measured numbers, dated. The rules come from the product
constitution ([product.md](product.md) §4.9): measured end-to-end, primary-sourced, conceding
rivals' real strengths — and **never comparing warble's engine time to a competitor's full round
trip**. The harness lives in [`scripts/bench/`](../scripts/bench/); a smoke of it runs in every
`scripts/regression.sh` pass.*

**Measured 2026-07-11** on: MacBook Pro, Apple M4 Max (16 cores), 64 GB RAM, macOS 26.5.1
(25F80); warble 0.2.0 + the in-progress 0.3 work tree, debug build; Parakeet =
`sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8` via sherpa-onnx v1.13.2; whisper.cpp not installed
on this machine (rows would appear if it were). Numbers on your machine will differ — rerun the
commands; that's what they're for.

---

## 1. End-to-end latency

**What is measured.** The paste-path pipeline, exactly as the app runs it, over a committed
fixture WAV (`scripts/bench/fixtures/e2e-fixture.wav`, 2.5 s, "The quick brown fox jumps over
the lazy dog"): **WAV → transcription chain → spoken-spelling pass → cleanup (Light, the
default) → dictionary → paste-ready string**, timed in-process by the debug binary's
`--bench-e2e` flag — the same leg order as `DictateController`. Cold = a fresh process with the
warm ASR server stopped first (the true first-dictation-after-launch path: server spawn + model
load + transcribe). Warm = the daily path, engine already loaded, run 1 discarded as warm-up.

```
cd apps/macos && swift build
sh scripts/bench/latency.sh --runs 10                          # cold + warm, the app's real chain
sh scripts/bench/latency.sh --engine apple --no-cold --runs 5  # pin one engine (DEBUG seam)
```

**Results (N=10, 2.5 s clip, cleanup Light):**

| Path | Median | p95 | Notes |
| --- | --- | --- | --- |
| Warm (Parakeet warm server — the daily path) | **64.6 ms** | 75.9 ms | run-to-run 61–76 ms |
| Cold (first dictation: server spawn + model load) | **916.1 ms** | 933.0 ms | worst case, see below |
| Apple Speech, forced (N=5) | 49.4 ms | 141.7 ms | the zero-install floor; accuracy is the tradeoff (§2) |
| Parakeet cold-spawn per clip, forced (N=5) | 1398.3 ms | 1450.4 ms | the no-warm-server fallback |

**What the harness cannot reach, estimated honestly.** A scripted run has no mic and no focused
text field, so three legs of the real release-of-key → text-landed experience are excluded:
key-up handling (an event-tap callback, ~1–5 ms), recorder stop + WAV finalize (file close +
header write, single-digit ms), and the paste event itself (pasteboard write + synthetic ⌘V,
~1–5 ms to post, plus the target app's own insert-and-render, typically tens of ms and outside
any dictation app's control). **Add roughly 20–60 ms to the harness numbers** for a realistic
release-to-text-visible figure; the harness number is the floor, not the claim. An in-app
signpost measurement is the planned upgrade.

**Cold is gentler than it looks.** The app starts warming engines on key-*down*, overlapping the
~0.9 s server start with your speaking — a first dictation longer than the warm-up hides the
cold cost entirely. The number above is the unhidden worst case.

**The comparison rule.** Wispr Flow claims p99 < 700 ms and is independently observed at ~1.8 s
real-world round trip ([competitive/wispr-flow.md](competitive/wispr-flow.md)). warble's
comparable figure is **the harness number plus the estimated excluded legs (~85–125 ms warm)**
— never the raw engine time, and never our harness median against their observed round trip as
if the two methods were the same. The launch-grade proof stays what the roadmap says it is: one
side-by-side video, both apps, same sentence, same machine.

## 2. Word error rate

**What is measured.** Pooled WER — (substitutions + deletions + insertions) / reference words,
word-level Levenshtein alignment, case- and punctuation-insensitive, contractions and number
formatting strict ("3" ≠ "three") — scored by the unit-tested scorer in
[`scripts/bench/wer.ts`](../scripts/bench/wer.ts). Corpus: the ten public-domain Harvard
sentences (List 1, `scripts/bench/fixtures/harvard.txt`) rendered by macOS `say` at two voices ×
two speaking rates (here: Samantha and Daniel × 175/220 wpm) = 40 clips, 320 reference words.
Engines are pinned one at a time via the DEBUG `WARBLE_FORCE_ENGINE` seam — no silent fallback
ever contributes to another engine's number.

```
sh scripts/bench/wer-corpus.sh                    # synthesizes the corpus, scores every installed engine
sh scripts/bench/wer-corpus.sh ~/my-recordings    # your own corpus: clip.wav + clip.txt pairs
```

**Results (synthetic corpus, 40 clips / 320 words):**

| Engine | WER | Errors | Notes |
| --- | --- | --- | --- |
| Parakeet (warm or cold — same model) | **0.9%** | 3 (3 S) | warble's preferred engine |
| Apple Speech | **11.9%** | 38 (28 S, 10 D) | the zero-install floor |
| whisper.cpp | — | — | not installed on this machine; the script scores it when present |

**The caveat that matters: this corpus is synthetic.** TTS audio is studio-clean, disfluency-free,
and prosodically regular — it **underestimates real-world WER** for every engine in the table.
The relative gap between engines on the same corpus is meaningful; the absolute numbers are a
ceiling, not a promise. A recorded human corpus drops into the same `clip.wav` + `clip.txt`
layout with zero harness changes — that's the planned upgrade, including a personal-jargon set.
For the same reason, **do not** place these numbers next to Wispr Flow's independently measured
~97% accuracy: different corpus, different method, meaningless comparison. A same-corpus
comparison is future work.

Also honest: the Apple row was measured through warble's own harness on a machine where the CLI
binary holds Speech authorization; on a machine where it doesn't, the script reports the engine
as unavailable and skips it rather than guessing.

## 3. Idle footprint

**What is measured.** RSS and CPU for warble.app and each warm server, sampled from `ps` every
5 s over 2 minutes while idle (no dictation, no read-aloud). CPU is Δcputime / Δwalltime across
the whole window — the honest idle figure, not `ps`'s decaying average. The sampler only
observes; run it twice for the on/off comparison.

```
bun scripts/bench/footprint.ts --minutes 2 --interval 5   # once with servers warm, once after they exit
```

**Results (idle, 24 samples over ~2 min each):**

| State | Process | RSS avg | CPU avg |
| --- | --- | --- | --- |
| Servers off | warble (app) | **75.0 MB** | 0.01% |
| Servers warm | warble (app) | 75.0 MB | 0.00% |
| | ASR server (Parakeet, warm) | **1834.1 MB** | 0.02% |
| | TTS server (Kokoro, warm) | **517.8 MB** | 0.02% |
| | **Total** | **2427.0 MB** | **0.03%** |

Not measured this run: the MLX polish LLM server — it loads only when Cleanup is set to
Medium/High (the default, Light, never starts it), and it failed to start standalone during this
run (noted for investigation); its RSS would add to the warm total on machines using LLM polish.

**The honest reading.** The critic predicted warble's warm engines might rival Wispr Flow's
community-benchmarked ~800 MB idle RAM. Measured: warble's warm state is **~2.4 GB — three times
larger**. That number ships anyway (product.md §4.9). The other side of the trade is also real:
the RAM buys the 65 ms warm path (§1), idle **CPU** is ~0.03% against Wispr's community-reported
~8% (different machines, different methods — treat as orders of magnitude, not a benchmark), and
with servers off warble is a 75 MB native app that still dictates on the Apple floor. Today the
only way to shed the warm RAM is quitting warble; the roadmap's prescription stands: **a "warm
engines" toggle** (trade latency for RAM, user's choice, off-state registers nothing) **is
warranted by this number** and belongs in 0.3's reliability work.

---

## Re-running everything

```
cd apps/macos && swift build                      # the harness drives the DEBUG binary
sh scripts/bench/latency.sh --runs 10             # §1
sh scripts/bench/wer-corpus.sh                    # §2
bun scripts/bench/footprint.ts --minutes 2        # §3 (run twice: servers warm / off)
sh scripts/regression.sh                          # includes the harness smoke (stub engine, no models needed)
```

The stub engine (`WARBLE_FORCE_ENGINE=stub`, DEBUG builds only) exists so the harness itself is
testable on any machine with no premium engines and no Speech authorization — it proves the
plumbing, never a number.
