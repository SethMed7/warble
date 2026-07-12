# Changelog

All notable changes to **warble** (formerly **voz**). Versions are Sparkle-published; each entry
is what a user actually gets.

## Unreleased

*The 0.3 reliability core — "never lose a word": dictations survive crashes and failed pastes,
failures name their cause, long sessions cap cleanly instead of truncating silently, cleanup is a
level you choose (verbatim-leaning by default, raw transcript always kept), every performance
claim is measured — and all of it is provable by one deterministic command. Plus 0.4 — "the
first five minutes" — in full: the welcome tour with permission cards that never dead-end and a
guaranteed first success for both verbs, engine setup without the wait trap, the listening
contract, and the whole milestone folded into the same regression suite. And 0.5 — "cheap
parity" — in full: Snippets (spoken trigger phrases that expand into saved text), "press
enter" auto-send (end a dictation with the phrase and warble sends it, off by default),
multi-shortcut + mouse bindings (put push-to-talk on a thumb button), the dictate →
read-back proofreading loop (⌃R as a dictation lands reads it back with the follow-along —
the loop only a bidirectional voice app can close), and the same suite consolidation, extended:
the auto-send and read-back secure-field claims are now unit-tested, not just documented. And
0.6 continues — "context, locally": context awareness, opt-in, bounded, and inspectable, off by
default — the capture half (what was read is always visible), the apply half (the captured
category shapes per-app tone: casual in chat, code-aware in terminals, formal in mail — with
context off, output is provably byte-identical to before), the inspect half (any dictation that
read context shows exactly what, right in History, next to the raw-transcript reveal — and Clear
history takes it all with it), and now the dashboard retention pass: WPM framed against published
typing averages, "corrections cleaned for you," word counts in human units, a streak heatmap,
visible dictionary learning in the recent feed, and a locally-rendered "Save a stats card" — Wispr
Flow's stickiest surface, with zero telemetry.*

- **The welcome tour — sequential permission cards (0.4 begins).** First launch now opens a card
  flow instead of the static welcome page: welcome → **Microphone** → **Accessibility** → done,
  one permission per card with a one-line plain why ("to hear you — audio never leaves your
  Mac"), a button that triggers the real system prompt where the API allows (mic) or deep-links
  straight to the exact System Settings pane, and a live status that flips to a checkmark the
  moment the grant lands — Next enables on grant or skip. Every card is skippable, skipping the
  whole tour is always one click, and it never reappears uninvited: existing installs never see
  it (the old first-run flag is honored), and **menu → Welcome tour…** reopens it anytime.
  Speech Recognition is deliberately not a card — only the Apple-fallback engine needs it, and it
  prompts contextually. After a macOS update, warble now silently re-verifies previously-granted
  permissions; if the update revoked one (macOS is known to do this to Accessibility), the menu
  shows **one quiet notice row** — click it to fix in System Settings; never a dialog, never
  repeated once acknowledged, auto-retired if the grant comes back. Under the hood the flow is a
  pure, unit-tested state machine the rest of the 0.4 onboarding steps will plug into; headless
  proof: `--onboarding-state` prints the machine, a DEBUG `--render-onboarding` seam renders
  every card to a real @2x PNG offscreen, and `scripts/regression.sh` asserts both.
- **Guaranteed first success — the tour's second half (0.4 continues).** After the permission
  cards, the tour now proves both verbs before you leave, and ends in your own app:
  - **"It hears you"** — a live mic-level meter (the pill's electric waveform idiom) moving with
    your voice before any dictation is asked for. Nothing is recorded or transcribed — buffers
    reduce to one level and vanish — and the tap runs only while the card is visible. If the mic
    was skipped, the card says so plainly and offers **Back to Microphone** — never a dead end.
  - **"Try a dictation"** — a practice dictation inside the card with the real gesture: hold
    **Fn**, say the deliberately messy prompt (*"Umm, let's meet Friday at 3 — no, actually
    4pm"*), release. The cleaned result lands in the card with the raw transcript struck through
    beneath it — the cleanup visibly working. It's a true rehearsal: the result is routed into
    the card (never pasted into whatever app focus wandered to) and **never touches History,
    stats, or the recent-dictations menu**.
  - **"Hear it back"** — a paragraph in the card + select it and press **⌃V**: the REAL read-aloud
    fires, follow-along panel and all, and a read while the card is up lights Next. Accessibility
    skipped → the plain notice + **Back to Accessibility**.
  - **"Now do it in your own app"** — the finish card opens **Mail, Notes, or Messages** (apps
    every Mac has) with the one line that matters: hold **Fn** and talk wherever the cursor is.
    **Done** ends the tour permanently; only **menu → Welcome tour…** brings it back.

  Every new card is still skippable and Next gates on the practice/read cards actually firing (or
  a skip). Headless proof, extended: every card and preview-state variant renders to a real @2x
  PNG (`--render-onboarding meter` / `practice+done` / `read+noax`…), the state machine's new
  steps + jump-back are unit-tested, and a new `--practice-sim` flag + regression check prove the
  sandbox invariant on disk: a rehearsal records nothing while a control dictation still lands.
- **Engine setup without the wait trap (0.4 continues).** The premium-engine download is the
  classic local-app first-five-minutes killer; Setup now takes the sting out of every part of it:
  - **Sizes up front.** Every engine card states its download size AND disk footprint before any
    consent — measured against the real artifacts (HTTP content-lengths of the pinned tarballs
    and repos, `du` of finished installs), not folklore: Sharper dictation ~510 MB down / ~0.9 GB
    on disk, Neural voices ~140 MB down (+ ~95 MB voices on the first read — stated, so nothing
    ever downloads unannounced) / ~0.5 GB, AI cleanup ~0.9 GB down / ~1.1 GB. Each card also says
    **where it lands** (weights → the store you picked, runtime → `~/.warble`), live with the
    "New downloads" choice.
  - **Resumable downloads.** Bytes stream into a `<file>.part` next to the destination and an
    interrupted download — network drop, app quit — **resumes from where it stopped** (HTTP
    Range); a server that ignores the range gets an honest restart, never a corrupt append. The
    reuse-on-reinstall promise extends to partials: a re-run never re-downloads bytes that are
    already present and valid, and a finished file is verified by size and never fetched twice.
    The shell-script installers gained the same resume (`curl -C -`).
  - **Progress that never lies.** The bar exists only when real bytes back it (a resumed
    download honestly starts partway along); phases that report nothing — unpacking, venv
    setup — show their **name** with the spinner, never a fake percentage or a stalled bar. Also
    fixed: the doubled ellipsis in phase labels, and the system controls that couldn't take the
    design system's focus ring (the store picker and progress bar are now warble's own).
  - **Non-blocking, and it says so.** Installs run in the background and archives unpack into a
    hidden staging dir that's renamed into place atomically — a dictation mid-install can never
    see (or load) a half-written model. While anything installs, Setup says the thing that
    matters: *you can keep dictating on your current engine.*
  - **Later never nags.** Audited every path that surfaces Setup: the menu item, the tour's
    finish card (its one mention, as a quiet option), and a hover tooltip — nothing auto-opens,
    badges, or re-prompts. Closing Setup without installing is a permanent-quiet decline; the
    one-time dashboard-tutorial handoff now happens only on the first finish (a later **Done**
    just closes the window).

  Headless proof: `--engine-sizes` prints the verified size/destination table (asserted verbatim
  in `scripts/regression.sh`, like `--errors` — drift means re-verify); a DEBUG `--render-setup`
  seam renders every Setup state (fresh / installing / installed / failed) to a real @2x PNG; a
  DEBUG `--fetch-resume` seam plus a loopback Range fixture server prove resume byte-for-byte
  (truncated partial resumes with only the remainder transferred, complete dest costs one HEAD,
  full-length partial promotes without a refetch, ignored range restarts) with **zero external
  network**; the resume decision matrix is unit-tested in `swift test`.
- **The listening contract (0.4 continues).** "Did it hear me?" now has three unmissable answers:
  - **Sounds.** A soft ping the moment the mic actually goes hot, and a quieter, lower one on a
    clean stop (release, hands-free stop, or the cap's clean stop) — synthesized in-process, so
    there's no asset and nothing to download. Cancel and error paths stay silent (their named
    states already speak). Toggle under **Dictate ▸ Sounds** — on by default, one click to turn
    off, and off *stays* off; nothing ever re-enables itself.
  - **Honest phases, end to end.** The pill's three states are now visually unmistakable: the
    electric waveform reacts only while the mic is hot, a flat line + spinner means transcribing,
    and a new **brief electric checkmark** blinks as the text lands — then the pill is gone
    (transient as ever). Fixed on the way: the spinner used to keep spinning for a beat after the
    paste landed — motion now stops the instant its phase ends.
  - **Hover shows the gesture.** Hovering the pill — any state — widens it to show the active
    gesture in place: *hold Fn · Esc cancels* while recording (*double-tap Fn to stop* in
    hands-free), *Esc cancels* while processing. Discoverability without a manual.

  Headless proof: a new `--sounds` flag round-trips the toggle across processes; a DEBUG
  `--render-pill` seam renders every pill state — live waveform, hover hint, cap countdown,
  spinner, checkmark, clipboard/error pills — to a real @2x PNG offscreen; the ping synthesis
  and hint copy are unit-tested; and `scripts/regression.sh` gained a `listening` check
  asserting all of it.
- **The first five minutes, folded into the durable suite (0.4 complete).** Everything the
  milestone shipped is now proven by the same one command: the onboarding machine's order, skip
  paths, first-run migration, and jump-back (`swift test` + `--onboarding-state`), every tour
  card and preview variant, every Setup state, and every pill state rendered offscreen to real
  @2x PNGs, the practice card's rehearsals-never-recorded invariant on disk, the verified
  engine-size table, byte-level download resume against a loopback fixture server, and the
  sounds toggle that stays off. New for human design review: `scripts/onboarding-gallery.sh`
  renders the complete card gallery — every tour card, Setup state, and pill state, 26 @2x
  PNGs — to `/tmp/warble-onboarding-qa` in one command, and a `gallery` regression check keeps
  that command from rotting. [docs/testing.md](docs/testing.md) grew the 0.4 coverage map, the
  render-seam reference, and the by-hand list — headed by **the fresh-account five-minute
  test**, the milestone's exit criterion, written as an exact timed script (both verbs landing
  in a real app inside 5:00, zero verbal help).
- **Honest numbers, measured.** The benchmark harness lands in `scripts/bench/` and the first
  real numbers in [docs/benchmarks.md](docs/benchmarks.md) — method, caveats, and a reproduction
  command for every figure, per the product constitution (product.md §4.9: measured end-to-end,
  never engine-time vs a competitor's round trip). Three benchmarks: **end-to-end latency**
  (fixture WAV → transcribe → clean → dictionary → paste-ready string, cold and warm, N=10
  median/p95 via a new `--bench-e2e` flag that times the app's exact paste-path pipeline
  in-process), **WER** (a synthetic `say`-rendered Harvard-sentence corpus scored per engine by a
  tested TS scorer — real recorded corpora drop into the same wav+txt layout), and **idle
  footprint** (RSS + Δcputime CPU for the app and each warm server, on vs off — the warm ASR
  server's honest ~1.8 GB is published, with the roadmap's "warm engines" toggle noted). A
  DEBUG-only `WARBLE_FORCE_ENGINE` seam pins a run to one engine so no number is ever a silent
  fallback's; the harness smoke (stub engine, fixture WAV, wer/stats unit tests, footprint
  self-row) is wired into `scripts/regression.sh`.
- **Dictation recovery — never lose a word.** While you dictate, the audio is now written
  incrementally to a crash buffer under `~/.warble/inflight` (owner-only, bounded, independent of
  the Save-recordings setting), so a crash or force-quit mid-dictation can't cost the words: the
  next launch quietly offers **menu → Dictate → Recover Last Dictation**, which transcribes the
  clip through the normal pipeline into History — never auto-pasted. A **failed transcription now
  lands as a FAILED History item** (recording kept, warn glyph) with replay and a **Re-transcribe**
  button that runs the pipeline again and resolves it in place. Clean endings promote or delete the
  buffer as before; stale clips are cleaned at launch; **Clear** removes the buffer with everything
  else. Headless proof: `--recover-scan` (plus the `WARBLE_HOME` sandbox seam), wired into
  `scripts/regression.sh` — an orphaned in-flight WAV with the stale header a crash leaves is
  repaired, recovered, and asserted to land in history with its audio intact.
- **Long-session hardening — a 20-minute cap, never a silent cut.** Very long holds used to be
  silently truncated: the recorder stopped writing at 5 minutes and a hidden watchdog force-ended
  the session mid-hold with no warning and no explanation. Now one number owns the story: a
  dictation is capped at **20 minutes** (the category norm — Wispr Flow's cap — and inside
  Parakeet's ~24-minute single-pass window), the pill shifts to a visible warning for the final
  minute (warn glyph + a live "stops in 0:59" countdown while the waveform keeps reacting — the
  mic is still hot), and at the cap the session stops **cleanly**: everything captured is
  transcribed, lands normally, and the pill + menu name why ("hit the 20-minute cap"). The
  recorder's runaway ceiling now sits a margin *above* the cap, so audio is never dropped before
  the clean stop. Headless proof: `WARBLE_MAX_HOLD_SECS` (debug builds) compresses the cap;
  `--hold-cap` prints the resolved cap/warn/stop-copy story and `--hold-cap-sim` drives the real
  session clock in seconds — both asserted in `scripts/regression.sh`.
- **Cause-naming errors.** Every failure in the dictate and read-aloud flows now names its cause —
  "mic is in use by another app", "mic disconnected mid-dictation", "engine still warming up — try
  again in a moment", "premium engine not installed — using Apple engine" (a one-time notice, never
  a nag), "transcription failed — recording kept" — in the pill/panel (warn + glyph for true
  failures), in the menu (an honest Engine row plus a "Last error" row until the next successful
  dictation), and in the unified log with a stable `reason=` slug per branch
  (`log stream --predicate 'subsystem == "io.github.sethmed7.voz"'`). A **failed transcription now
  keeps the recording** under `~/.warble/audio` (honoring the Save-recordings and secure-field
  settings) instead of discarding it — surfaced as a FAILED History item (see *Dictation
  recovery* above). A mic that
  disconnects mid-dictation delivers everything captured up to the drop. Debug builds accept
  `WARBLE_FAULT=mic-busy|mic-disconnected|engine-warming|engine-missing|transcribe-fail` to force
  each path; `--errors` prints the whole taxonomy, asserted verbatim in `scripts/regression.sh`.
- **Cleanup levels.** **Dictate ▸ Cleanup** replaces the "Polish with AI" toggle with four levels:
  **None** (verbatim — whitespace only), **Light** (the deterministic tidy — the default),
  **Medium** (on-device LLM punctuation + fillers — the old polish), and **High** (fuller LLM
  formatting latitude, still guarded so it can't change your words). Verbatim-leaning by default,
  per the product constitution; an explicitly set "Polish with AI" preference migrates
  (on → Medium, off → Light). Headless proof: `--cleanup <none|light|medium|high> "text"` and
  `--cleanup-level`, both wired into `scripts/regression.sh`.
- **Undo-polish.** Every dictation now also keeps the **raw transcript** (text only, no extra
  audio) whenever cleanup changed it; open a History item and click *"what you actually said"* to
  see it — or restore it as the transcript in one click.
- **The trill.** The mark redesigned as five thick sound-wave bars — rise, crest, dip, crest
  (*war·ble*) — deliberately few and heavy so it's unmistakable at menu-bar size. The app icon is
  cleaned (real transparency — no more white ring in the Dock), the menu-bar glyph draws full-bleed
  with ~3× thicker bars, and the logo / showcase / brand boards were regenerated — the last
  voz-era art (stale "VOZ TYPES" copy, wrong hotkey, dead space) is gone.
- **The plan, written down.** [docs/product.md](docs/product.md) defines what warble is and will
  never do; [ROADMAP.md](ROADMAP.md) stages 0.3 → 1.0 with an explicit go-public gate; and a
  verified multi-agent competitive teardown of Wispr Flow lives in
  [docs/competitive/](docs/competitive/wispr-flow.md).
- **One regression gate, now a durable suite.** `scripts/regression.sh` proves everything above
  in one deterministic command: named checks (`--list` to see them, `--only <check>` for fast
  iteration) covering the core acceptance suite, a debug build, all four cleanup levels, the
  cause-naming seams, recovery end-to-end — including a new headless `--retranscribe` that
  resolves a FAILED history item in place, and a raw-transcript-persistence check for
  undo-polish — the session cap, and a smoke of the benchmark harness. Dictate's pure logic
  (the BasicCleaner twin runs the *same* cases as `core/clean.test.ts`, plus spell-out, cap math,
  and the hallucination filter) moved into a real SwiftPM test target run via `swift test`.
  Engine-free by default (`WARBLE_REGRESSION_FULL=1` adds the warm-engine extras); every check is
  sandboxed, so a run never touches your real `~/.warble`, dictionary, or preferences. The full
  guide — coverage map, env seams, what still needs a human — is
  [docs/testing.md](docs/testing.md).
- **Snippets (0.5 begins).** A spoken trigger phrase now expands into text you saved — a
  signature, an address, a canned reply — managed in a new **Snippets** dashboard section that
  follows Dictionary's exact layout: add/edit/delete, hairline rows, no boxes. Say the trigger
  alone and it replaces the whole dictation; say it inside a longer sentence and only that span is
  swapped. Matching is case-insensitive on word boundaries, tolerates any run of whitespace, and
  the longest matching trigger wins when two overlap (so "see you soon" beats "see you"). It runs
  after cleanup and the dictionary and before paste — at every cleanup level, including None, as
  long as you've defined at least one snippet (a trigger is your explicit intent, never AI
  rewriting) — so a spelling the dictionary just fixed can still trigger one. Stored at
  `~/.warble/snippets.json`, owner-only (0600), honoring `WARBLE_HOME` like the rest of the store.
  Headless proof: a new `--expand "text"` CLI flag (plus `--snippet-set` for the dashboard's write
  path), a pure matcher unit-tested in `swift test` (word boundaries, longest-match, no recursive
  expansion, case-insensitivity, multi-line expansions), and a `scripts/regression.sh` check
  covering trigger-alone, trigger-in-sentence, the no-snippets passthrough, the dictionary-then-
  snippets ordering, and the 0600 file.
- **"Press enter" auto-send (0.5 continues).** End a dictation by saying **"press enter"** (or
  "press return") and warble sends it — huge for chat apps: hold Fn, dictate a message, say the
  phrase, release, and it's already sent. **Off by default** (**Dictate ▸ Press Enter to Send**;
  never re-enables itself once turned off) and recognized ONLY when it's the very last thing you
  say — the phrase is stripped from what gets pasted, but the exact same words anywhere earlier in
  the dictation ("if you press enter here it submits") are left completely untouched, so dictating
  instructions about the feature still works. Case-insensitive, tolerates trailing punctuation
  ("press enter." / "press enter!"), and runs as the final leg of the pipeline (cleanup → dictionary
  → snippets → auto-send). The Return keystroke fires only after a successful paste and never in a
  secure (password) field — it reuses the same secure-field signal InsightStore already gates
  history recording on. When it fires, the pill's landed checkmark says so ("sent — said 'press
  enter'") so the behavior is never mysterious; when the toggle is off, the phrase pastes verbatim,
  no hint, no nag. Headless proof: a pure `AutoSend.detectFinal` unit-tested hard (final-position
  matrix, mid-sentence negatives, punctuation variants, newline-preserving strip), a new
  `--autosend "text"` CLI flag reading the persisted toggle, a `--render-pill landed+sent` seam for
  the pill's new feedback state, and a `scripts/regression.sh` check covering the toggle gate, the
  strip, and the render.
- **Multi-shortcut + mouse bindings (0.5 continues).** Fn isn't the only trigger anymore: bind up
  to three more — **right ⌘**, **right ⌥**, an F-key (**F13–F19**), or a **mouse button (3–10)**,
  thumb buttons included — each as hold-to-talk or a double-tap hands-free toggle, in a new
  **Shortcuts** dashboard section (also **Dictate ▸ Shortcuts…** in the menu). Built for the RSI /
  accessibility case where dictation lives on a mouse thumb button. Bindings are **aliases of Fn,
  not modes**: identical hold and double-tap timing, the same pill, the same Esc cancel, the same
  everything — and Fn itself stays, shown locked in the editor as the built-in default. Changes
  apply live (the tap re-registers, no relaunch; a dictation mid-flight is delivered first, never
  dropped), and like everything per-mode, **nothing registers while Dictate is off**. The picker
  offers only keys and buttons macOS leaves free — Esc, ⌃V, the click buttons, and the system's
  own F-keys can't even be picked — and a duplicate or fourth binding is rejected inline with a
  plain reason. Honest by construction: warble only *listens* for a binding (the monitor observes,
  never consumes), so the key or click still does whatever it normally does — pick one your apps
  don't use. Headless proof: the binding model's pure halves (spec parse/format, conflict
  rejection with reasons, load-time hygiene, event-matching key codes, monitor teardown) are
  unit-tested in `swift test`; a new `--bindings [add|remove]` CLI flag prints the active trigger
  table and runs the dashboard's exact validation; and a `scripts/regression.sh` check proves the
  default (Fn only), the defaults-seam and add/remove round-trips across processes, every
  rejection reason, and that a hand-planted invalid array degrades to Fn-only instead of wedging
  the tap.
- **Dictate → read-back — the proofreading loop (0.5 continues).** The moment a dictation lands,
  the pill's checkmark carries a quiet *"⌃R to hear it back"* — press **⌃R** and warble reads
  your just-landed words aloud through the real read-aloud pipeline: the follow-along panel
  tracking word by word, your chosen voice, your dictionary's pronunciations, **Esc** stops.
  Speak to type, then hear what you typed — the bidirectional loop as a single workflow, and the
  one feature a dictation-only app can't copy. The hotkey is **transient by design** (product.md
  §4.6): the ⌃R claim registers only when a dictation lands and releases on use, on a new
  dictation, or after a **15-second grace window** — long enough to re-read what landed and want
  it in your ears, short enough that ⌃R (your terminal's reverse-search) is never shadowed a
  minute later. **Dictate ▸ Read Last Dictation Back** reads the last dictation any time (no
  window) so the loop is discoverable and hotkey-optional. Per-mode law throughout: with Read
  aloud off, the menu item sits disabled, the pill shows no hint, and ⌃R never registers — and a
  read-back never arms after a secure-field dictation (a spoken password is never read out
  loud). Stats stay honest by construction: a read-back routes through the same one-shot read
  path as the Services entry, so it logs exactly **one** read-aloud usage — never two. Headless
  proof: the availability machine is pure and unit-tested (`swift test` ReadBackTests), a new
  `--readback-state` flag tells its whole story for `scripts/regression.sh` (asserted verbatim),
  and the landed pill's new affordance renders via `--render-pill landed+readback` into the
  design-review gallery.
- **Cheap parity, folded into the durable suite (0.5 complete).** Auditing the milestone's four
  features against the regression suite surfaced one real gap: the auto-send and read-back
  secure-field claims ("never in a password field") were true in code but proven only by a
  comment and a by-hand test. Both are now unit-tested directly — `AutoSend.mayFireReturn` and
  `ReadBackAvailability.landed`'s `secure` parameter are the exact gates
  `DictateController.deliver` calls, pulled out so the safety claim can't silently drift — and
  told headlessly: `--autosend "…" --secure` proves the phrase still strips while the Return
  keystroke never fires, and `--readback-state` grew a line proving a secure landing never arms
  ⌃R even with read-aloud on. Everything else the milestone shipped was already covered as it
  landed: the snippet matcher's word-boundary/longest-match/case/multi-line matrix, the
  cleanup→dictionary→snippets→auto-send pipeline order, the bindings table's defaults-seam
  round-trip and every rejection reason, and the read-back availability machine's full story.
  `scripts/onboarding-gallery.sh` already carried the milestone's two new renderable pill states
  (`landed+sent` and `landed+readback`, 28 PNGs total). [docs/testing.md](docs/testing.md) gains
  the updated coverage map, the secure-field gates, and a **Snippets, in the dashboard** entry to
  the by-hand list, alongside real mouse-button push-to-talk, a real auto-send in a chat app, and
  the full dictate→⌃R loop with audio.
- **Local-only context awareness — the capture half (0.6 begins).** A new **Context awareness**
  toggle in **Dashboard ▸ Data & Privacy** — **off by default**, opt-in, and it never turns
  itself back on (product.md §4.5) — lets warble read a small, bounded sliver of context at the
  moment a dictation starts: the frontmost app's identity (already captured for per-app stats), a
  category derived locally from a small built-in bundle-id list (mail / chat / editor / document /
  other), and at most **~200 words** of text near the cursor (the end of the field — nearest where
  you're writing) via the same focused-field Accessibility read learn-from-edits already uses — no
  new AX surface. Never screenshots, never other windows or apps, and never a secure (password)
  field: the off and secure gates run **before** any Accessibility read, so nothing is captured at
  all — not even the app. The captured text lives in memory for that one dictation and has no
  encodable form; History keeps only a compact, inspectable note of what was read — app, category,
  word count, and a ≤12-word preview whose cap is structural (the note's only initializer derives
  it, unit-tested down to "the 13th word is unencodable"). Old history lines still decode.
  Captured context is never handed to any network-capable code path — its only consumers are
  DictateController → the in-memory DictationContext → InsightStore's bounded ContextRecord — and
  the Dictate module's only network I/O is the loopback link to warble's own local engines.
  Headless proof: a new `--context-sim` seam runs the real capture gate over a fixture text file,
  and `scripts/regression.sh` gains a `context` check — the OFF default prints "context: off —
  nothing read" with no setup (the load-bearing negative), ON captures the bounded sliver with the
  exact 200-word/12-word caps, a simulated secure field captures nothing, and off stays off across
  processes. The gates, category heuristics, caps, and record schema are unit-tested
  (ContextAwarenessTests). What context awareness *does* with the sliver is the next bullet
  (per-app tone); surfacing the note in the dashboard is the milestone's remaining step.
- **Per-app tone — the apply half (0.6 continues).** The captured category now shapes the output,
  deterministically first: dictate a short command into a **terminal or editor** and the ASR's
  trailing period is dropped ("git status." → "git status"; identifier casing and technical
  tokens are never touched — no sentence-case forcing, and "main.py" is not a sentence boundary);
  a short **chat** message loses its stiff trailing period too (contractions pass through, `!`
  and `?` always stay, longer or multi-sentence messages keep their punctuation); **mail and
  documents** keep today's full punctuation, and an app warble can't place changes nothing. The
  rules live in the canonical cleaner (`core/clean.ts`) and its Swift twin, additive and gated on
  category — with **context awareness off (the default) output is byte-identical to before**,
  proven by a golden no-change regression check (a fixed input set through every cleanup level
  against pre-change goldens). At **Medium/High** the category also rides the polish prompt as
  exactly one destination-hint line — still bounded by the same words-changed safety guard, and
  byte-identical prompts when no category was captured; at **None/Light** the LLM stays out of it
  entirely (None remains a pure passthrough, tone rules included). Your dictionary and snippets
  always win: they run after the tone pass, so a learned casing or a snippet's own punctuation is
  never undone. Headless proof: a new `--clean-in-context <category> "text"` seam, the tone rules
  unit-tested twin-for-twin (clean.test.ts + BasicCleanerTests), the prompt hint + None-gate
  unit-tested, and a `context-apply` regression check covering the goldens, every category, and
  the dictionary/snippets precedence end to end.
- **Inspectable, not just promised — the inspect half (0.6 continues).** Any dictation that
  captured context now shows exactly what, right in **History**: open it, and a quiet line sits
  next to *"what you actually said"* — `context: Mail (mail) · 42 words read · "Re: the Q3
  numbers…"` — mist text, no accent, no box, no toggle; a dictation made with the setting off
  shows nothing there at all (no empty-state noise). **Data & Privacy** gains the verification
  line the toggle deserves: *"Check any dictation in History to see exactly what was read."*
  **Clear all history** takes every one of those notes with it — the record rides
  `DictationEvent`, so clearing history clears it too; turning **Context awareness** off (it stays
  off) stops any new capture, and the notes already made stay inspectable until you clear them.
  Codable backward compatibility keeps holding: pre-0.6 history lines (0.3 through 0.5 — none of
  them ever had a `context` field) still decode in full, proven against a committed fixture, not
  just an inline case. Headless proof: a new `--render-history` (DEBUG) seam rasterizes the real
  History detail — the exact WARBLE_HOME → InsightStore → view wiring, not a fixture view in
  isolation — so a legacy dictation renders with no context row and a context-bearing one renders
  the row; `--history-count` proves the decode count off a seeded store; `--clear-history` (DEBUG)
  proves the record dies with the rest. `scripts/regression.sh` gains a `context-inspect` check
  covering all three claims, and the record→display formatting (truncation preserved verbatim, the
  singular/plural word count, the empty-preview/missing-field case, the app-name → bundle-id →
  "unknown" fallback) is unit-tested (ContextAwarenessTests). ROADMAP 0.6's context-awareness
  bullet — capture, apply, inspect — is now complete.
- **The dashboard retention pass (0.6 continues).** Home tells a week's story at a glance, every
  number still locally computed and honest — zero telemetry. Your **WPM** is now framed against
  published typing averages, never a fabricated dictation-population percentile warble has no data
  for ("you speak at 142 wpm — ~3.5× the average typist"). A new **corrections cleaned** counter
  sits right under it on Home — "8 corrections cleaned up for you" — the fillers/false-starts/
  duplicates the cleanup pipeline actually removed, measured at clean time and stored on the
  dictation. Word counts now also read in **human units** — "~14 pages · ~2 emails a day" — off
  widely-cited, plainly-documented conversion constants, never presented as precise fact. A
  **streak heatmap** (a GitHub-style day grid of the last ~12 weeks, tinted in nothing but the one
  accent) sits next to the existing day-streak stat. The recent feed now shows a **"warble learned:
  `<word>` — from your correction"** row the moment the dictionary auto-learns a word from an
  in-place edit — the same moment `LearnPill` already confirms live, just made visible in the
  dashboard's story too, kept in its own file so it can never skew WPM/streak/per-app stats. And
  one button, **"Save a stats card,"** renders a branded PNG (the trill mark, three headline
  stats, the real voice gradient — the one declared identity-surface exception to the in-app
  one-accent rule) to wherever you choose via a real Save panel — fully local, no sharing
  integrations, no network, and a failed write now surfaces a plain alert instead of silently
  doing nothing. Headless proof: `BasicCleaner.correctionsCount` and a new `RetentionTests` suite
  unit-test the WPM/typist framing, the corrections-cleaned headline, the human-unit math, and the
  heatmap's calendar bucketing (empty history, a single busy day, a real DST spring-forward
  boundary against an injected timezone, and a non-Gregorian-system-calendar mismatch that used to
  render the whole grid empty despite real data); `--corrections-count` and `--learned-count`
  re-prove the counting/decoding CLI seams, and new `--render-home`/`--render-share-card` (DEBUG)
  seams rasterize Home — now showing the corrections-cleaned line — for both an empty and a fully
  populated WARBLE_HOME, and the share card itself at its real fixed size —
  `scripts/regression.sh` gains a `retention` check and the card gallery grows to 33 renders.

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
