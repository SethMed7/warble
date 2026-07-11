# warble — testing

*How warble's promises are proven. One deterministic command covers everything 0.3 and 0.4
shipped; this page maps what it checks, the seams it uses, and the short list that still needs a
human — headed by the fresh-account five-minute test, 0.4's exit criterion.*

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
| `unit` | `swift test`: the BasicCleaner Swift twin passes the **same cases** as `clean.test.ts` (the twin-drift guard), plus SpellOut, HoldCap math, the hallucination filter, the onboarding state machine (step gating, skip paths, first-run gate migration, post-update re-verify, practice/read completion gating, the backward-only jump-back), the resumable-download decision matrix (206 append / 200 restart / 416 verify + Content-Range parsing + file:// plumbing), and the listening contract's pure halves (ping synthesis: subtle-by-construction, click-free, decaying, tiny; the pill's gesture-hint copy) | cleanup / cap logic / 0.4 onboarding + engine setup + listening contract |
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
| `onboarding` | `--onboarding-state` declares the welcome tour's steps in order (welcome → mic → ax → meter → practice → read → finish), every step parseable and skippable, the demonstrations constant-complete and practice/read constant-incomplete headlessly; every declared card **plus every preview-state variant** (granted permissions, the meter/practice skipped-mic looks, the practice card's landed raw→cleaned transformation, the read card's done/no-accessibility looks) renders offscreen to a real 920×1080 @2x PNG via `--render-onboarding` (DEBUG seam — no window, no permissions, fixture states injected) | 0.4 permission cards + first success |
| `practice` | the practice card's sandbox invariant: `--practice-sim` runs the real pipeline (stub engine) and pushes the result through the store's record gate tagged `sandbox` — History/stats must not move — then as the control dictation, which must land; the on-disk `history.json` (under `WARBLE_HOME`) holds exactly the control event | 0.4 guaranteed first success |
| `setup-sizes` | `--engine-sizes` states the verified download/disk/destination table verbatim (the numbers were measured against the real artifacts — drift means re-verify, exactly like `--errors`), and every Setup card state (fresh / installing / installed / failed) renders offscreen to a real @2x PNG via `--render-setup` (DEBUG seam — width exact at 1120, height the content's own) | 0.4 engine setup friction |
| `setup-resume` | resumable downloads byte-for-byte against a loopback fixture server (`scripts/fixtures/range-server.ts`, 127.0.0.1 only — the suite never touches the real network) whose request log shows what crossed the wire: a truncated `.part` resumes with `Range: bytes=<n>-`, a complete dest costs one HEAD and zero data, a full-length partial verifies (416 + HEAD) and promotes without a refetch, an ignored range restarts honestly; the resume decision matrix itself is unit-tested (`swift test`) | 0.4 engine setup friction |
| `listening` | the listening contract's headless halves: the start/stop pings' toggle round-trips through UserDefaults **across processes** via `--sounds` (default on — the ping is the contract; off *stays* off, product.md §4.5), and every pill state renders offscreen to a real @2x PNG via `--render-pill` (DEBUG seam — no panel, no mic; representative bar levels and a frozen spinner injected): the live listening waveform, the hover-revealed gesture hint, the cap countdown, the processing spinner, the landed checkmark, and the clipboard/error text pills — wave-pill dims asserted exactly, text-bearing states must out-width their textless base | 0.4 listening contract |
| `gallery` | the card gallery stays runnable: `scripts/onboarding-gallery.sh` renders **every** onboarding card (+ variants), Setup state, and pill state into one directory in one command — the check runs the real script into a sandbox and asserts every PNG lands, recomputing the expected count from the machine's declared steps so a new card can't miss the gallery | 0.4 design review |
| `warm` | (opt-in) a premium engine is active and `--speak` renders a real read-aloud | — |

Three layers, by design: **pure logic** lives in unit tests (`core/clean.test.ts` for TS,
`apps/macos/Tests/` for Swift — DictateTests plus SharedTests for the onboarding machine and the
resumable-fetch logic; `swift test` shares `swift build`'s artifacts, so it adds seconds, not a
second build);
**flows** live in headless CLI checks against the debug binary (the same code paths the app
runs, minus UI — for onboarding that includes rendering every card to a PNG); the **harness**
that produces public numbers gets its own smoke so a broken script can't quietly stop the
benchmarks being reproducible.

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
| `WARBLE_FORCE_ONBOARDING=1` | any | reopen the welcome tour on launch without resetting the first-run keys (QA re-entry; **menu → Welcome tour…** is the user path) |
| `MEMEX_AI_HOME` | any | relocate the shared model store (default `~/.memex/ai`) — pins the destination paths `--engine-sizes` prints |
| `WARBLE_REGRESSION_FULL=1` | — | include the warm-engine checks in a full regression run |

## The render seams + the card gallery

Onboarding and first-run UI is renderable **headlessly** (DEBUG builds only, like the other debug
seams): each flag rasterizes the exact live view offscreen at @2x with fixture state injected —
no window, no window-server ordering, no permissions, no mic. Every new UI step must extend one
of these seams; the regression checks above assert real pixels through them.

| Flag | Renders |
| --- | --- |
| `--render-onboarding <step[+variant]> <out.png>` | one tour card — step ids from `--onboarding-state`; variants inject preview state: `mic+granted`, `ax+granted`, `meter+nomic`, `practice+done`, `practice+nomic`, `read+done`, `read+noax` |
| `--render-setup <state> <out.png>` | the Setup window in one state: `fresh` \| `installing` \| `installed` \| `failed` |
| `--render-pill <state> <out.png>` | the pill: `listening` \| `listening+hint` \| `listening+cap` \| `processing` \| `processing+hint` \| `landed` \| `copied` \| `error` |

For human design review, one command renders all of them — every tour card and variant, every
Setup state, every pill state (26 PNGs, `@2x`):

```sh
sh scripts/onboarding-gallery.sh          # → /tmp/warble-onboarding-qa (pass a dir to override)
```

Review the output against [DESIGN.md](../DESIGN.md). The suite's `gallery` check runs this same
script, so the gallery command can never silently rot.

## What remains manual

These need a mic, a screen, or twenty real minutes — each has a scripted twin above proving the
logic, so the by-hand pass is about the *experience*. Run the debug app with a seam by launching
the binary directly (no flags = the full app): `cd apps/macos && WARBLE_FAULT=mic-busy .build/debug/warble`.

### The fresh-account five-minute test — 0.4's exit criterion

**The milestone gate (ROADMAP 0.4):** a fresh Mac account reaches a successful real-app dictation
AND one read-aloud inside five minutes, with **no verbal instructions**. Run it with a human who
has never used warble. You watch silently, timer in hand; every stall you'd want to explain away
is the bug.

**Setup (before the clock):**

1. Build the release dmg (`sh scripts/release.sh`) or take the latest released one — the test is
   release-build territory (real TCC prompts, real Gatekeeper).
2. **System Settings → Users & Groups → Add User** — a brand-new macOS account, then log into it.
   (Fresh TCC state: no permission ever granted to warble; no premium engine installed — the tour
   must succeed on the Apple floor.)
3. Open the dmg, drag warble to Applications. Don't launch it yet.
4. Hand over the seat and say exactly this, nothing more: *"Launch warble and follow what it
   shows you. I can't answer questions."*

**The clock starts at first launch.** The targets (cumulative — drift is fine, 5:00 isn't):

| Target | What must happen on its own | Watch for |
| --- | --- | --- |
| 0:00 | Launch → the welcome tour opens by itself | no hunting in the menu bar |
| 0:30 | **Microphone** card → its button raises the real system prompt → grant → status flips to the checkmark → Next lights | do they find the button unprompted? |
| 1:15 | **Accessibility** card → deep-link lands on the right Settings pane → grant → the card's status flips live | the flip must happen while Settings is still open |
| 1:45 | **It hears you** — the bars move with their voice, settle in silence | do they speak without being told to? |
| 2:45 | **Try a dictation** — hold Fn, the messy prompt line, release → the cleaned sentence lands in the card, raw struck beneath | the gesture understood from the card alone, first try |
| 3:30 | **Hear it back** — select the in-card paragraph, ⌃V → the real read fires, follow-along panel and all | |
| 4:30 | **Finish card** → they click Mail / Notes / Messages → hold Fn and dictate a real sentence → it lands at the cursor | **criterion 1: a real-app dictation** |
| 4:55 | In that same app: select the dictated sentence, ⌃V → it reads aloud | **criterion 2: a real read-aloud** |

**Pass:** both criteria inside 5:00 with zero words from you. **Fail:** any stall you broke with
words, any dead-end card, or the clock passing 5:00 — write down the exact card and moment; that
is the milestone's bug list. **Afterwards, verify the sandbox:** open the dashboard — History
must hold exactly the real dictation(s), never the practice rehearsal; then quit and relaunch —
the tour must not reappear (only **menu → Welcome tour…** brings it back).

### The rest of the by-hand list

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
- **The pings, heard**: hold Fn — a soft higher ping the moment the mic opens (never before), a
  quieter lower one on release; the same pair for hands-free and for the cap's clean stop.
  Esc-cancel and every error path stay silent. **Dictate ▸ Sounds** off silences both, survives a
  relaunch, and never comes back on by itself. (The synthesis and the toggle's persistence are
  the scripted twins — `swift test` + `--sounds`; this pass is your ears.)
- **Hover the pill, live**: mid-recording, mouse over the pill — it widens in place with
  *hold Fn · Esc cancels* (*double-tap Fn to stop* in a hands-free session) and narrows back on
  mouse-out, waveform undisturbed; while processing it shows *Esc cancels*; on the clipboard/error
  pills the hint is *hold Fn to dictate*. (Every hover look is rendered headlessly by
  `--render-pill`; this pass is the tracking itself.)
- **The landed checkmark**: after a paste lands, the spinner must become a brief electric ✓ and
  the pill must be gone well under a second — no spinner ever visible after the text has landed.
- **The paste itself** (+ Copy Last Dictation, Recent Dictations) into real apps — editor,
  terminal, Slack.
- **Read-aloud**: ⌃V watch → selection queue → follow-along highlighting → collapse → Esc.
- **The welcome tour, end to end**: `WARBLE_FORCE_ONBOARDING=1 .build/debug/warble` (or, for the
  true first-run path, clear the debug domain's keys first: `defaults delete warble
  didShowOnboarding; defaults delete warble didShowWelcome`) — walk the cards: the mic card's
  button raises the real system prompt and the status flips to the checkmark while the card is
  up; the Accessibility card deep-links to the right Settings pane and flips live on grant;
  "Skip for now" moves on without it; "Skip tour" closes in one click; the tour never reopens by
  itself, and **menu → Welcome tour…** brings it back. (The machine logic itself — order, gating,
  skip paths, migration, jump-back — is already covered by `swift test` and `--onboarding-state`.)
- **The meter card, with a real mic**: on the "It hears you" card the bars must move with your
  voice and settle in silence; they must be **still before the card appears and after it goes**
  (Next, jump back, window close — motion only while the card is visible). With the mic skipped,
  the card must say so and **Back to Microphone** must land on the mic card with Next gated again.
- **The practice card, real gesture end to end**: on "Try a dictation", hold **Fn**, say the messy
  prompt line, release — the pill runs (waveform → spinner), the cleaned sentence lands in the
  card's field with the raw transcript struck through beneath, and Next lights. Then verify the
  sandbox: dashboard History gains **no** row, Home stats don't move, and **Copy Last Dictation**
  does not offer the rehearsal. A dictation made with another app frontmost while the card is up
  is real (pasted + recorded) — the sandbox only owns dictations aimed at the card.
- **The read demo card**: select the in-card paragraph, press **⌃V** — the REAL read fires
  (follow-along panel, voice, Esc all normal), and the card's status flips to the checkmark,
  lighting Next while it's up. With Accessibility skipped, the card says so and **Back to
  Accessibility** returns to that card.
- **The finish card**: **Mail / Notes / Messages** buttons each open the real app; do the "own
  app" dictation there within the minute. **Done** ends the tour for good (it never reopens
  itself; only the menu brings it back).
- **Post-macOS-update re-verify**: needs a real OS update (the stored `kern.osversion` must
  change) with a permission revoked behind warble's back — the menu must show the one quiet
  notice row, clicking it must open the right Privacy pane and retire it, and it must not
  reappear. The decision logic is unit-tested; this by-hand pass is about the row itself.
- **The real benchmark numbers**: `scripts/bench/` against real engines on real hardware —
  method, caveats, and reproduction commands in [benchmarks.md](benchmarks.md). The suite only
  smokes the harness; the published numbers are gathered by hand, per the constitution
  (product.md §4.9).
- **Dictating while an engine installs**: start a big install in Setup (Sharper dictation is the
  slowest), then hold Fn and dictate — the pill must run normally on the current engine the whole
  time, and Setup's "you can keep dictating" line must show while anything installs. The
  can't-load-a-half-model logic (partials as `.part`, staged unpack) is proven headlessly by
  `setup-resume`; this by-hand pass is about the experience.
- **A real network resume**: mid-install, turn Wi-Fi off until the card fails, turn it back on,
  hit **Retry** — the bar must pick up near where it stopped, not at 0% (the byte-level twin is
  `setup-resume`; this proves it against real CDNs).
- **Sparkle updates and engine Setup** — release-build territory (both involve the network by
  design: the two disclosed calls).

## Adding a check

A feature without a regression check is incomplete. In `scripts/regression.sh`: write a
`check_<name>()` function (use the `expect` / `step` helpers; sandbox everything you touch; pin
and restore any defaults you read), add the name to `ALL_CHECKS`, and give it a `describe` line.
Engine-free is the bar — if the feature needs a warm engine, put the check behind
`WARBLE_REGRESSION_FULL=1`; if it genuinely can't be headless, add its by-hand procedure to the
list above.
