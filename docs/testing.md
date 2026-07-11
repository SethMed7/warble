# warble — testing

*How warble's promises are proven. One deterministic command covers everything 0.3 shipped; this
page maps what it checks, the seams it uses, and the short list that still needs a human.*

## The one command

```sh
sh scripts/regression.sh
```

Run from the repo root. It exits `0` only when **every** check passed, and it is **engine-free by
default**: every default check passes on a machine with no premium engines installed, no Speech
authorization, and no UI — so it runs anywhere, including CI.

```sh
sh scripts/regression.sh --list                    # name every check
sh scripts/regression.sh --only cleanup            # one check, for fast iteration
sh scripts/regression.sh --only recovery,retranscribe   # a subset (comma or repeat --only)
WARBLE_REGRESSION_FULL=1 sh scripts/regression.sh  # + the warm-engine extras
```

`--only` assumes the debug binary already exists — run `--only build` first when in doubt.
Everything the suite touches is sandboxed: fixture dictionaries via `WARBLE_DICTIONARY`,
throwaway stores via `WARBLE_HOME`, and the unbundled debug binary's own `warble` defaults
domain (never the installed app's) — your real `~/.warble` and preferences are never involved.

## What the suite covers

| Check | Proves | 0.3 feature |
| --- | --- | --- |
| `core` | the canonical TS cleaner's acceptance suite (`core/clean.test.ts`, via `bun test`) | cleanup foundation |
| `build` | a debug `swift build` succeeds and produces the CLI binary | — |
| `unit` | `swift test`: the BasicCleaner Swift twin passes the **same cases** as `clean.test.ts` (the twin-drift guard), plus SpellOut, HoldCap math, and the hallucination filter | cleanup / cap logic |
| `version` | `--version` matches `Info.plist` | — |
| `cleanup` | all four levels: None is verbatim, Light equals the deterministic `--clean`, Medium/High degrade to the deterministic result with no LLM | cleanup levels |
| `cleanup-level` | the level persists across processes; an old "Polish with AI" preference migrates (on → medium) | cleanup levels |
| `dictionary` | `--apply` / `--pronounce` over a fixture dictionary; repeated corrections promote at the learn threshold | dictionary |
| `selftest` | learn-from-edits detection + history-event codability (incl. the `raw` field and `failed` status round-trips) | undo-polish, recovery |
| `engine` | `--engine` names a real tier (Apple Speech is the zero-install floor) | — |
| `errors` | the cause-naming taxonomy verbatim (`--errors` — copy drift is deliberate), and the two faults provable headlessly: `engine-missing` names its cause and forces the Apple floor; `transcribe-fail` names its cause and exits non-zero | cause-naming errors |
| `hold-cap` | the 20-minute cap story resolves exactly; a compressed real clock (`--hold-cap-sim` at 4s) warns **before** it stops, then stops cleanly | long-session hardening |
| `recovery` | an orphaned in-flight WAV (stale crash header) is repaired, lands as a FAILED history event with its audio kept, the orphan is consumed, and the scan is idempotent | dictation recovery |
| `retranscribe` | a FAILED event resolves **in place** when the pipeline re-runs over its kept recording (`--retranscribe`, stub engine), raw transcript persisted | recovery + undo-polish |
| `recover-raw` | the happy recovery path persists **both** the cleaned text and the verbatim raw transcript through the real store | undo-polish |
| `bench` | the benchmark harness itself: WER/stats math (`bun test` + an exact `wer.ts` check), the latency harness end-to-end over the committed fixture WAV through the stub engine, the footprint sampler's `ps` parsing | honest numbers |
| `warm` | (opt-in) a premium engine is active and `--speak` renders a real read-aloud | — |

Three layers, by design: **pure logic** lives in unit tests (`core/clean.test.ts` for TS,
`apps/macos/Tests/DictateTests` for Swift — `swift test` shares `swift build`'s artifacts, so it
adds seconds, not a second build); **flows** live in headless CLI checks against the debug binary
(the same code paths the app runs, minus UI); the **harness** that produces public numbers gets
its own smoke so a broken script can't quietly stop the benchmarks being reproducible.

## The env seams

Debug-build seams are compiled out of release builds (`#if DEBUG`) — they can never alter shipped
behavior. The sandbox seams work in any build.

| Seam | Build | What it does |
| --- | --- | --- |
| `WARBLE_FAULT` | debug | force one failure path: `mic-busy` \| `mic-disconnected` \| `engine-warming` \| `engine-missing` \| `transcribe-fail` |
| `WARBLE_MAX_HOLD_SECS` | debug | compress the 20-minute session cap so the warn→stop machine runs in seconds |
| `WARBLE_FORCE_ENGINE` | debug | pin the transcription chain to exactly one engine (`parakeet-warm` \| `parakeet` \| `whisper` \| `apple` \| `stub`) — no silent fallback; `stub` is the engine-free fixed-utterance transcriber the suite runs on any machine |
| `WARBLE_HOME` | any | relocate the whole `~/.warble` store (history, audio, in-flight buffer) to a sandbox |
| `WARBLE_DICTIONARY` | any | point the dictionary at a fixture file instead of the real one |
| `WARBLE_DISABLE_LLM` | any | hide an installed on-device LLM, so Medium/High provably fall back |
| `WARBLE_REGRESSION_FULL=1` | — | include the warm-engine checks in a full regression run |

## What remains manual

These need a mic, a screen, or twenty real minutes — each has a scripted twin above proving the
logic, so the by-hand pass is about the *experience*. Run the debug app with a seam by launching
the binary directly (no flags = the full app): `cd apps/macos && WARBLE_FAULT=mic-busy .build/debug/warble`.

- **The three mic faults** (`mic-busy`, `mic-disconnected`, `engine-warming`): launch with the
  fault, hold Fn and speak — the pill must show the exact taxonomy copy (see `--errors`), the menu
  must show a "Last error" row until the next successful dictation, and `mic-disconnected` must
  still deliver everything captured up to the drop.
- **The pill's cap countdown**: launch with `WARBLE_MAX_HOLD_SECS=90`, hold Fn past the warning —
  the countdown ("stops in 0:59…") must tick while the waveform stays live, and the cap must stop
  the session cleanly with everything captured transcribed and the cause named. The full-length
  version of this test is a real 20-minute hold.
- **Crash recovery, end to end**: mid-dictation, `kill -9` the app; relaunch — the menu must
  quietly offer **Dictate ▸ Recover Last Dictation**, and one click must land the words in History
  (never an auto-paste).
- **Re-transcribe in the dashboard**: on a FAILED History item — replay works, one
  **Re-transcribe** click resolves it in place.
- **Undo-polish in the dashboard**: open a History item where cleanup changed the text — *"what
  you actually said"* shows the raw transcript, and restore puts it back as the transcript.
- **The paste itself** (+ Copy Last Dictation, Recent Dictations) into real apps — editor,
  terminal, Slack.
- **Read-aloud**: ⌃V watch → selection queue → follow-along highlighting → collapse → Esc.
- **The real benchmark numbers**: `scripts/bench/` against real engines on real hardware —
  method, caveats, and reproduction commands in [benchmarks.md](benchmarks.md). The suite only
  smokes the harness; the published numbers are gathered by hand, per the constitution
  (product.md §4.9).
- **Sparkle updates and engine Setup** — release-build territory (both involve the network by
  design: the two disclosed calls).

## Adding a check

A feature without a regression check is incomplete. In `scripts/regression.sh`: write a
`check_<name>()` function (use the `expect` / `step` helpers; sandbox everything you touch; pin
and restore any defaults you read), add the name to `ALL_CHECKS`, and give it a `describe` line.
Engine-free is the bar — if the feature needs a warm engine, put the check behind
`WARBLE_REGRESSION_FULL=1`; if it genuinely can't be headless, add its by-hand procedure to the
list above.
