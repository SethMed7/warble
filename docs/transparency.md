# warble — transparency

*Every hook warble installs, every byte it stores, every packet it sends — and the command that
lets you check each claim yourself. Written for the reader who arrives with Little Snitch,
`strings`, and healthy suspicion (ROADMAP 0.7; the standard is product.md §4.9: measured,
primary-sourced, no overclaims). Everything below is written from the shipping code, with the
source file named so you can read the mechanism instead of trusting the prose. If any line here
doesn't survive your own check, that's a bug — file it.*

*Applies to warble 0.2.x and the current `main`. Paths assume a default install.*

## The short version

- warble's network behavior is **exactly three things**: (1) Sparkle's update check against the
  signed appcast, (2) consented model downloads in Setup, and (3) loopback-only links
  (`127.0.0.1`, proxies hard-disabled) to warble's own local engine servers. Nothing you speak,
  read, type, or store is on any of those wires. [Details + destinations](#network-behavior).
- warble hooks input in five ways — the dictation triggers, the read-aloud watch session, and
  three Carbon hotkeys (⌃V while Read aloud is on; ⌃R and Esc only mid-session) — plus one
  opt-in Accessibility text read and one post-paste keystroke watcher (the most sensitive thing
  warble does, [owned plainly below](#learn-from-edits--the-keystroke-shadow-watcher)).
- What warble remembers lives in **four places**, not one: `~/.warble` (history, audio,
  dictionary), the preferences plist (`io.github.sethmed7.voz` — settings only, never content),
  the model stores (`~/.memex/ai`, `~/.cache`, or `~/.warble/llm` — your choice at Setup), and
  `~/.bun` (a runtime). [The full map](#what-warble-stores).

---

## What warble hooks, and why

macOS input hooks come in two kinds, and the difference matters: **NSEvent monitors** observe
events and structurally cannot consume, delay, or alter them (the key still does whatever it
does); **Carbon hotkeys** claim one exact key combination and do consume it. warble uses both,
each scoped to a mode you can switch off — and a mode that's off registers *nothing*
(product.md §4.5).

### The dictation triggers (Fn + your bindings)

- **What:** one global + one local NSEvent monitor for `flagsChanged` + `keyDown` — enough to run
  the hold / double-tap state machine for Fn and any bindings you added. The monitored set grows
  only with your bindings: `keyUp` joins only if you bound an F-key, `otherMouseDown/Up` only if
  you bound a mouse button (3–10). `keyDown` is watched even with no bindings so a chord
  (Fn+arrow, right-⌘ C) is told apart from a deliberate bare hold and never starts a dictation.
- **What it never does:** consume anything. Monitors are observers by construction — a bound key
  or button still performs its normal action in every app.
- **When:** installed while Dictate is on; torn down entirely when you toggle Dictate off.
- **Source:** `apps/macos/Sources/Dictate/HotKey.swift` (`register`/`unregister`, `mask(for:)`).
- **Permission:** Accessibility (macOS delivers global key events only to trusted apps).
- **See for yourself:** toggle **Dictate** off in the menu — Fn and every binding go dead
  instantly (`HotKey.unregister` removes the monitors; the suite's `bindings` check unit-tests
  the teardown).

### Learn-from-edits — the keystroke-shadow watcher

This is the single most sensitive hook warble has, so here is its full scope, plainly:

- **What:** after **every** successful paste, in **every** app, while **Learn from edits** is on
  (it is **on by default**), warble installs a global + local `keyDown` monitor and a global
  `leftMouseDown` monitor for up to **25 seconds**. During that window warble's process sees your
  keystrokes system-wide. It replays them onto an in-memory shadow copy of the text *it just
  pasted* — printable keys insert, Backspace/Delete remove, ◀ ▶ move a caret — and when the text
  settles it diffs the shadow against what was pasted.
- **Why:** to learn spelling corrections without reading any app's text — fix "Miele" to "Myela"
  right after a dictation lands and warble tallies the pair; enough repeats and the dictionary
  learns it (you see it happen: the learn pill + a "warble learned" feed row).
- **The bail conditions** (read `handleKey` — any of these stops the watcher on the spot, and it
  learns nothing): a left mouse click · any ⌘/⌃/⌥ chord · ↑/↓/Home/End/PageUp/PageDown/Esc (caret
  jumps it can't follow) · Return/Enter/Tab (judge once, then stop) · the 25-second deadline · a
  new dictation starting.
- **What can ever be kept:** at most one `(from → to)` word pair, and only when the edit was a
  clean single-word swap **of a word warble itself typed**, spelling-close by edit distance. The
  shadow buffer itself is in-memory and discarded — no keystroke log exists anywhere, in memory
  or on disk, beyond that transient shadow.
- **Source:** `apps/macos/Sources/Dictate/KeystrokeLearner.swift` (monitors installed at
  `start`, lines ~36–40; bail logic in `handleKey`); wired in
  `DictateController.startLearning`. The diff rules are static helpers in
  `CorrectionListener.swift` (`words`/`detectCorrection` — exercised by `--selftest`). There is
  no other learn-from-edits mechanism: an earlier Accessibility-polling watcher in that file was
  never wired into the app and has been deleted.
- **Permission:** Accessibility (`AXIsProcessTrusted` gates `start` — without it, nothing
  installs).
- **Off switch:** **menu → Dictate → Learn from edits.** Off stays off, and off installs nothing.
- **See for yourself:** with it on, paste a dictation and press ⌘A — the watcher bails instantly
  (a chord); or fix one word and watch the learn pill count the correction. With it off, no
  monitor exists to bail.

### Read aloud — ⌃V and the watching session

- **⌃V itself** is a Carbon hotkey (`RegisterEventHotKey`), registered while Read aloud is on —
  it consumes exactly ⌃V and nothing else, and is unregistered the moment you toggle the mode
  off. Source: `SpeakController.registerHotKey`/`unregisterHotKey`.
- **The watching session** is the part to understand: pressing ⌃V starts a session that installs
  **two global mouse monitors** (`leftMouseDown` records the click position, `leftMouseUp`
  classifies the gesture) which run until watching stops — the first Esc or the ✕ button ends
  the watch (reading continues; a second Esc or ■ then closes the session), and the menu toggle
  or the auto-close a few seconds after the reading queue drains tear the whole session down.
  For as long as the watch runs, **every gesture that looks like a
  selection** — a drag longer than ~4 points, a double/triple-click, a shift-click — triggers an
  automatic grab of the current selection: warble synthesizes **⌘C** (a posted CGEvent), waits
  for the pasteboard to change, reads the text, then **restores your clipboard** to exactly what
  it held (all item types, not just text). Plain single clicks are observed too — down/up
  position, click count, and the shift flag, exactly what classifying the gesture needs — but
  never trigger a grab. This is a deliberate continuous watch-and-grab loop —
  it's what lets you queue selections by just highlighting them — and it runs *only* inside a
  session you started with ⌃V and ends with Esc.
- **Nothing is retained** beyond the session: each grabbed selection is displayed verbatim in the
  follow-along panel (the panel *is* the disclosure — everything captured is on screen), spoken,
  logged to local history as a "read" event — its text only while **Keep history** is on; off, the
  row keeps just the metrics (word count, app, voice), never the text — and the synthesized audio
  chunks are deleted as they finish playing.
- **Source:** `apps/macos/Sources/Speak/SpeakController.swift` (`installMonitors`/
  `removeMonitors`, `captureCurrentSelection`) and `Speak/SelectionGrabber.swift` (the
  borrow-and-restore).
- **Permission:** Accessibility (posting the synthetic ⌘C requires it; the first use prompts).
- **See for yourself:** while no session is live, highlight anything — nothing is grabbed and
  your clipboard never moves (the mouse monitors exist only between ⌃V and the end of the
  watch — at the latest, the session's close).
  During a session, watch the panel mirror every selection you make — that's the whole take.
  And toggle **Read aloud** off: ⌃V is a normal key again (in Terminal it types a literal ⌃V),
  because the hotkey itself is unregistered with the mode.

### ⌃R — the transient read-back claim

- **What:** a Carbon hotkey for ⌃R that exists only in the ~15 seconds after a dictation lands
  (and only if Read aloud is on and the field wasn't secure). Consumed once or expired, it is
  unregistered — ⌃R is your terminal's reverse-search again. Never a standing hotkey.
- **Source:** `apps/macos/Sources/Dictate/ReadBack.swift` (`ReadBackKey.register`/`unregister`;
  the availability machine is unit-tested and printed by `--readback-state`).
- **See for yourself:** in a terminal, press ⌃R — reverse-search fires, always, except within
  ~15s of a dictation landing. Wait 16 seconds and it's reverse-search again.

### Esc — a claimed key, only mid-session

- **What:** a Carbon hotkey for Esc registered only while a dictation is recording/processing or
  a read-aloud session is live, released the moment neither is. Source:
  `apps/macos/Sources/Shared/EscapeKey.swift` (claim/release; the hotkey exists only while a
  claim does).

### Accessibility reads — exactly one, and it's opt-in

warble's only Accessibility *text read* is **context awareness** (Dashboard ▸ Data & Privacy —
**off by default**, never re-enables itself):

- At recording start — and only then — it reads the focused element's text, clips it to the
  **last 200 words** (nearest your cursor), derives an app category locally (a small static
  bundle-id map + keyword fallback), and keeps that sliver in memory for that one dictation. The
  gates run **before** the read: toggle off, or a secure field focused → the focused element is
  never even queried. What persists is only a compact note — app, category, word count, a
  preview capped at **12 words and 120 characters** (structural: the note's type cannot hold
  more) — visible on that dictation's History detail, deleted by Clear history. The in-memory
  sliver itself dies with its dictation: taken exactly once on the deliver path, and dropped on
  every abort path (mic error, empty/too-short/silent clip, Esc, mode off) — `SessionCapture`
  in `ContextAwareness.swift`, unit-tested.
- Never screenshots, never other windows, never other apps, never a password field.
- **Source:** `apps/macos/Sources/Dictate/ContextAwareness.swift` (`captureLive`); the AX read it
  calls is the shared focused-field read in `CorrectionListener.swift` — one place in the app
  reads focused text.
- **See for yourself:** `defaults read io.github.sethmed7.voz contextAwareness` (absent or 0 =
  off, the default); the regression suite's `context` check proves off-by-default, the bounds,
  the secure-field zero, **and** greps `ContextAwareness.swift` for networking symbols
  (`URLSession`, sockets, …) — the capture module is architecturally unable to reach a network.

Beyond that: learn-from-edits does **not** read field text (it shadows keystrokes, above);
pasting does **not** read the target app (it's a synthetic ⌘V, below); and `--axprobe` is a
diagnostic that reads the focused element **only when you run it by hand** from a terminal.

Secure-field detection — the thing several features gate on — is not an AX read either: it's
`IsSecureEventInputEnabled()` (a system flag) plus a short list of password-manager bundle ids
(`DictateController.passwordManagerBundleIDs`).

### Events warble posts (synthetic input)

- **⌘V** after each dictation: the paste is clipboard borrow-and-restore — your clipboard is
  saved, replaced with the transcript, ⌘V posted, and restored ~0.3s later
  (`Dictate/Paster.swift`).
- **Return**, only when **Press Enter to Send** is on (off by default) *and* you said the phrase
  in the final position *and* the field isn't secure (`Paster.postReturn`, gated in
  `DictateController.deliver`; the gate is unit-tested).
- **⌘C** during read-aloud sessions and Services/Read Selection (above).

### The microphone

- **Hot exactly while the pill is up in its listening phase**: the capture tap is installed when
  a hold crosses the ~0.2 s threshold (or a double-tap toggles hands-free on) and removed at
  release, Esc, or the 20-minute cap — there is no
  always-listening mode, no wake word, no VAD running in the background. A soft ping marks the
  moment the mic actually opens (and a lower one, a clean stop); the menu-bar icon fills while
  recording. Source: `Dictate/Recorder.swift` (`start`/`stop`).
- While hot, audio is written incrementally to `~/.warble/inflight/` — the **crash buffer** (see
  storage below) — so a crash can never lose your words.
- The onboarding **"It hears you"** card runs a level meter: an audio tap that reduces each
  buffer to one number and drops it — no file, no transcription — only while that card is
  visible, and only if the mic permission was already granted
  (`warble/Setup/MicMeter.swift`).
- **Permission:** Microphone, requested the first time you actually dictate — never at launch.
- **See for yourself:** macOS's own orange mic indicator tracks warble exactly: it appears as
  the pill's waveform starts and vanishes on release or Esc — before the processing spinner is
  even done. System Settings ▸ Privacy ▸ Microphone shows the grant.

### Speech Recognition (the Apple permission)

Used by exactly one engine: the zero-install **Apple fallback** (`AppleFileTranscriber` in
`Dictate/Transcriber.swift`) — file mode with `requiresOnDeviceRecognition = true`. If the locale
can't do on-device recognition it refuses; it never falls back to Apple's server. The permission
prompt fires only when that engine actually runs (i.e., no premium engine installed, or every
premium engine failed on a clip). With Parakeet installed, most users never see this prompt.

---

## What warble stores

Not everything warble remembers lives in `~/.warble` — the honest map is four places:
`~/.warble` (your data), the preferences plist (settings), the model stores (weights you
consented to), and `~/.bun` (a runtime). Content — transcripts, audio, context — lives **only**
in `~/.warble`.

### `~/.warble` — your data (owner-only: the directory is `0700`, content files `0600`)

| Path | What it is | Bounds + control |
| --- | --- | --- |
| `history.json` | JSON Lines, one event per line: id, timestamps, the cleaned text, the raw transcript (only when cleanup changed it), word count, duration, app, engine, kind (`dictate`/`read`), failure status, the context note, corrections-cleaned count | text omitted entirely in stats-only mode (Keep history off); no size cap — but fully visible, exportable, and clearable in Data & Privacy |
| `audio/<id>.m4a` | the saved recording per dictation, 16 kHz mono AAC (~0.25 MB/min); pre-0.1.8 `.wav` still read | only while **Save recordings** is on, never from a secure field; size shown live in Data & Privacy ("N recordings · X MB") |
| `inflight/` | the **crash buffer**: the in-flight WAV written while the mic is hot, so a crash mid-dictation never loses the words | exists regardless of Save recordings; bounded structurally — at most **5** clips, nothing older than **7 days**, header-only remnants deleted at scan (`Dictate/Recovery.swift`); every clean end of a session promotes or deletes it |
| `dictionary.json` | your corrections + pronunciations | relocatable (Dashboard ▸ Dictionary ▸ Choose…); editable + deletable per entry |
| `learned.json` | "warble learned a word" moments (the word + one mis-hearing) | cleared with history |
| `snippets.json` | trigger → expansion pairs you defined | editable in Dashboard ▸ Snippets |
| `insights-ai.json` | the cached weekly recap — exists only if you opted into Insights AI (off by default) | cleared with history |
| `llm-model` | a one-line marker: the path/id of the cleanup model you consented to | — |
| `asr-venv/` `llm-venv/` `asr-server.py` `llm-server.py` `kokoro/` `llm/` `sherpa/` | engine runtimes + warm-server scripts installed by Setup (and, on the warble-only choices, some weights — table below) | removed by deleting `~/.warble`; these runtime files (and the `llm-model` marker) keep default (`0644`) mode bits — no content in them, and the `0700` directory already blocks every other account |

**What Clear does** (Dashboard ▸ Data & Privacy ▸ Clear, or the headless `--clear-history`):
deletes `history.json`, `learned.json`, the whole `audio/` store, the `inflight/` crash buffer,
and `insights-ai.json` — every transcript, every recording, every context note, every derived
cache (`InsightStore.clearAll`). **What Clear deliberately does not touch:** your
`dictionary.json` and `snippets.json` (they have their own editors and per-entry delete) and
your preferences. **Export** writes the history events as one pretty-printed JSON array —
what's in the file is exactly what the dashboard shows.

Also honest: the last ~10 cleaned transcripts are kept **in memory only** (menu → Copy Last
Dictation / Recent Dictations, the mis-paste safety net) — never written to disk, gone at quit.

### Preferences — `~/Library/Preferences/io.github.sethmed7.voz.plist`

Settings persist in `UserDefaults`, not `~/.warble`. (The domain is the voz-era bundle id, kept
so Sparkle updates and your TCC permission grants survived the rename — plumbing only.)
**Settings only, never content**: no transcript text, no audio, no captured context ever lands
here. The full key list, falsifiable in one command:

```sh
defaults read io.github.sethmed7.voz
```

- **Modes + gestures:** `dictateEnabled`, `speakEnabled`, `handsFreeEnabled`, `dictateBindings`
  (your extra triggers, e.g. `right-command:hold`), `dictateSounds`, `autoSendEnabled`,
  `learnFromEdits`, `contextAwareness`.
- **Cleanup:** `cleanupLevel` (`none|light|medium|high`); a legacy `llmCleanupEnabled` from the
  pre-levels era is read once for migration.
- **Dictionary:** `dictionaryPath` (a filesystem path — present only if you relocated it),
  `learnThreshold`.
- **Voice + stores:** `voiceId`, `warbleVoicesTarget` (`shared`/`app` — where Kokoro weights land).
- **Data & Privacy:** `insightsHistory`, `insightsSaveAudio`, `insightsExcludeSecure`,
  `insightsAI`, `insightsAIAuto`, `warbleAutoUpdate`.
- **UI + one-time flags:** `warble.dockIcon`, `didShowOnboarding` (+ legacy `didShowWelcome`),
  `didShowTutorial`, `notedAppleEngine`, `warnedNoWatch`.
- **Permission re-verify** (the post-macOS-update check): `permMacOSBuild` (an OS build string),
  `permGrantedSet` (e.g. `["ax","mic"]`), `permRevokedNotice`.

That same `defaults read` will also show two families warble's own code doesn't write, so they're
disclosed here rather than left for you to find: **Sparkle's bookkeeping**
(`SUEnableAutomaticChecks`, `SUHasLaunchedBefore`, `SULastCheckTime`, `SUUpdateGroupIdentifier` —
persisted by the update framework once the app syncs your auto-update preference onto it) and
**macOS window-frame autosaves** (`NSWindow Frame warble.insights`, `NSWindow Frame
warble.setup` — window positions, written by AppKit; installs that ran pre-rename versions may
also carry legacy `NSWindow Frame voz.insights` / `voz.setup` entries).

### The model stores — where consented weights land

Setup states every size **before** you consent (the card, and `--engine-sizes` — numbers
measured against the real artifacts, re-verified when a pin changes) and shows the destination.
You pick the store: **Shared** (default — `~/.memex/ai`, reused by other local-first apps and by
reinstalls) or **"warble only"**:

| Engine | Download / disk | Shared store (default) | "warble only" |
| --- | --- | --- | --- |
| Sharper dictation (Parakeet + sherpa-onnx) | ~510 MB / ~0.9 GB | `~/.memex/ai/models` | `~/.cache/sherpa` |
| Neural voices (Kokoro) | ~140 MB + ~95 MB voices on first read / ~0.5 GB | `~/.memex/ai/models/kokoro` | `~/.cache/huggingface-transformers` |
| AI cleanup (Qwen2.5-1.5B-4bit via MLX) | ~0.9 GB / ~1.1 GB | `~/.memex/ai/models/qwen2.5-1.5b-instruct-4bit` | `~/.warble/llm/mlx-model` |

Precision notes, because they're easy to get wrong: the app installs the cleanup engine by
running `setup-cleaner.sh` in env-only mode (`WARBLE_SETUP_ENV_ONLY=1` — venv + server script
only, no download), then downloads the pinned MLX model **in-process** into the store you chose
(`EngineSetup.installCleanup`) — so on the "warble only" choice, cleanup weights *do* land
inside `~/.warble` (only Parakeet's and Kokoro's warble-only homes are the `~/.cache` paths).
Running the script by hand instead (outside the app) uses `mlx_lm` and lands in the Hugging Face
cache (`~/.cache/huggingface`) — a path the app itself never takes. On an **Intel Mac** (no MLX;
the in-app card says "Needs Apple Silicon") the script's fallback installs llama.cpp and a GGUF
model at `~/.warble/llm/model.gguf`. Small runtimes are always warble-local: the venvs and
server scripts under `~/.warble`, and the bun runtime at `~/.bun`. `MEMEX_AI_HOME` relocates the
shared root.

---

## Network behavior

warble's network behavior is exactly three things. Everything else — dictating, reading aloud,
cleanup, the dictionary, the dashboard, history — works with Wi-Fi off, and you should try that
(it's the first verification below).

### 1. The update check (Sparkle)

- **Trigger:** at most ~daily (`SUScheduledCheckInterval` 86400) while **Install updates
  automatically** (Data & Privacy) is on; always when you click **Check for Updates…** yourself.
  The toggle maps straight onto Sparkle's scheduled checker — off means no scheduled check.
- **Destination:** `https://raw.githubusercontent.com/SethMed7/warble/main/appcast.xml`
  (`SUFeedURL` in `Info.plist`). Accepting an update then downloads the dmg from
  `github.com/SethMed7/warble/releases` (GitHub redirects the asset to
  `objects.githubusercontent.com`).
- **Payload:** an HTTPS GET for the appcast (version metadata). Sparkle's system-profiling is
  not enabled — no hardware/usage profile rides the request, ever. Every update is verified
  against the EdDSA public key pinned in `Info.plist` (`SUPublicEDKey`) before it installs.

### 2. Consented engine downloads (Setup)

Nothing downloads before you click Install on a card that states the size and destination. The
complete host list, per engine:

- **Sharper dictation:** the pinned sherpa-onnx engine + Parakeet model tarballs from
  `github.com/k2-fsa/sherpa-onnx` releases (→ `objects.githubusercontent.com`). Resumable — an
  interrupted download keeps its `.part` and picks up where it stopped.
- **AI cleanup (Apple Silicon):** the pinned `mlx-community/Qwen2.5-1.5B-Instruct-4bit` repo
  from `huggingface.co` (the API listing + `/resolve/main/` files; large files redirect to
  Hugging Face's CDN, `cdn-lfs*.huggingface.co`).
- **AI cleanup (Intel Macs):** the in-app Setup gates this engine to Apple Silicon; the script
  fallback (`scripts/bootstrap.sh`, or running `apps/macos/scripts/setup-cleaner.sh` yourself)
  installs llama.cpp — **via Homebrew when you have it (`brew install llama.cpp`, which reaches
  Homebrew's hosts: `formulae.brew.sh` and `ghcr.io`)**, otherwise the latest release located
  via `api.github.com` — and the GGUF model from `huggingface.co` into `~/.warble/llm/model.gguf`.
- **Neural voices:** `bun install` of the kokoro-js package → `registry.npmjs.org`; if bun
  isn't on the Mac, its installer from `bun.sh` first. The ~95 MB voice weights download **on
  the first read**, not at install (the card says so) — from `huggingface.co`, into the store
  you chose.
- **The setup scripts themselves**, when run standalone rather than from the app bundle or a
  repo checkout, fetch their server/helper files from `raw.githubusercontent.com`.

### 3. Loopback-only links to warble's own engines

The warm engines are local servers warble spawns from your own `~/.warble` copies of the
portable `core/` helpers — `asr-server.py` (Parakeet, port 8765), `llm-server.py` (cleanup,
8766), `say-server.ts` (Kokoro, 8767). Each binds `127.0.0.1` **only** (read the bind call in
each file). The app talks to them over `Shared/LoopbackHTTP.swift` — an ephemeral session with
**proxies hard-disabled** (`connectionProxyDictionary = [:]`), so a configured system proxy can
never receive the request bytes — and the one streaming path that still uses curl (the TTS
render, `Speak/Speaker.swift`) passes `--noproxy "*"` for the same reason. The LLM server is
additionally spawned with `HF_HUB_OFFLINE=1`, so its runtime cannot phone Hugging Face at
dictation time even in principle.

### What never goes on the wire

Your audio, your transcripts (raw or cleaned), the captured context, your dictionary, snippets,
history, stats, and crash-buffer contents. There is no telemetry endpoint, no account system,
and no error reporting service. The context claim is enforced structurally, not just promised:
the regression suite greps `ContextAwareness.swift` for every networking-capable symbol
(`URLSession`, `NWConnection`, sockets, `URLRequest`…) and fails if one ever appears — captured
context's only consumers are the dictation controller, that dictation's in-memory context, and
the bounded note in your local history.

---

## The log — warble narrating itself

Every user-facing failure logs a stable slug to the unified log; transcript text is **never**
logged (`Shared/Log.swift` — content stays private even locally). Watch live:

```sh
log stream --predicate 'subsystem == "io.github.sethmed7.voz"' --level info
```

The slugs (each `reason=<slug>`): the dictate error taxonomy — `mic-permission`, `mic-busy`,
`mic-disconnected`, `no-mic`, `record-failed`, `engine-warming`, `processing-timeout`,
`transcribe-failed`, `transcribe-failed-kept`, `engine-missing`, `hold-cap` (the debug binary's
`--errors` prints the user-facing copy for each, and the suite asserts it verbatim) — plus the
session paths: `cancelled`, `no-clip`, `too-short`, `silent-clip`, `nothing-heard`,
`cleaned-empty`, `paste-denied`, `runaway-ceiling` (the recorder's stuck-key safety ceiling
engaged — the clean 20-minute cap should always stop a session first, so this slug is itself a
bug report), and read-aloud's `render-failed`, `read-cut-off`, `voice-missing`, `no-selection`.

One honesty note: a successful dictation is *mostly* quiet in the log, but not silent — e.g. a
first dictation can log `warm ASR not healthy in time — cold chain takes over` (info) and still
land perfectly via the cold engine, and an engine that errors mid-chain logs its fall-through
before the next engine delivers. An entry in the log is not an error toast you missed; the pill
and the menu's "Last error" row carry the user-facing failures.

---

## Release integrity

Three independent proofs travel with a release, each covering a different failure mode, plus a
documented path toward a fourth (bit-for-bit reproducibility) that doesn't exist yet — stated
honestly rather than claimed.

### 1. The binary itself — Developer ID + notarization

Every release is signed with a Developer ID Application certificate and notarized by Apple
(`apps/macos/scripts/release.sh`) before it's stapled into the `.dmg`. This is what Gatekeeper
checks on first launch, and what you can check yourself against the installed app:

```sh
codesign -dv --verbose=2 /Applications/warble.app   # signature + identifier
spctl -a -vv -t install /Applications/warble.app     # Gatekeeper's own verdict (notarized?)
```

### 2. Updates — Sparkle's EdDSA signature

The **in-app auto-updater** never trusts the network alone: every update is verified against the
EdDSA public key pinned in `Info.plist` (`SUPublicEDKey`) before it installs, and the private key
that signs each release (`sign_update`, run by `scripts/update-appcast.sh`) lives only in the
maintainer's login Keychain — never in this repo. This covers exactly one path: **update
delivery** through the app itself. See [Network behavior](#network-behavior) above for the full
mechanics.

### 3. Downloads — SHA-256 checksums

EdDSA doesn't help someone who grabbed the `.dmg` a different way — the GitHub release page
directly, a mirror, a friend's copy — and wants to confirm the bytes weren't altered. Since this
milestone (0.7), `release.sh` also records the DMG's SHA-256 into `dist/checksums.txt`
(`scripts/checksum.sh` — idempotent, one line per filename) and it ships as a release asset
alongside the `.dmg`:

```sh
shasum -a 256 -c checksums.txt
```

**Precision note:** this practice started with 0.7 (2026-07). The ten releases before it
(v0.1.0–v0.1.8, v0.2.0) each carry a signed, notarized `.dmg` but **no** `checksums.txt` asset —
backfilling their hashes from the already-published bytes is a deliberate, tracked manual step
(owner's call on timing), not a standing claim that every release has always shipped one. See
[docs/repo-audit.md](repo-audit.md) for the exact backfill commands.

These three mechanisms answer different questions and none substitutes for another: EdDSA proves
*this came from the update feed I trust*; SHA-256 proves *this file is exactly the bytes that were
published*; notarization proves *Apple scanned this and found nothing it blocks*.

### 4. Building from source — what's reproducible today, and what isn't

warble is **not** bit-for-bit reproducible yet, and this doc won't pretend otherwise. What *is*
true today:

- **Deterministic:** compiling the tagged source with the same Xcode/Swift toolchain
  (swift-tools-version 5.9, currently built with Swift 6.2 — `swift --version`) and the same
  `Package.resolved` (pinned dependency versions, Sparkle included) produces the same Swift
  bytecode for the same inputs — ordinary compiler determinism, nothing warble-specific.
- **Not deterministic — the signature and notarization ticket.** `codesign --timestamp` embeds a
  trusted timestamp at signing time, so re-signing byte-identical unsigned output twice yields two
  different signed Mach-O files; the notarization ticket Apple staples is issued per submission by
  Apple's own servers. Neither is a warble decision — it's how Apple's code-signing trust chain
  works everywhere.
- **Not deterministic — one build-path string.** SwiftPM auto-generates
  `resource_bundle_accessor.swift` per target, and it bakes the **absolute build directory path**
  in as a fallback constant (only reached if the primary, relative resource lookup fails — which
  it doesn't, in the shipped app). That means a build from a different checkout path (a different
  machine, a CI runner's `/Users/runner/...`, even the same repo cloned somewhere else) differs
  from Seth's own release build in that one literal. It's SwiftPM boilerplate, not warble code, and
  it's disclosed in full — including where it actually shows up in a shipped binary — in
  [docs/repo-audit.md](repo-audit.md).

**What a stranger can actually verify from source**, today:

```sh
git clone https://github.com/SethMed7/warble && cd warble/apps/macos
swift build -c release              # or: sh scripts/bundle.sh for an unsigned build/warble.app
sh ../../scripts/regression.sh      # same suite, same PASS/FAIL — from the repo root
```

An unsigned build made this way won't byte-match the distributed `.dmg` (no Developer ID, no
notarization — Gatekeeper will say so, correctly), but it lets anyone compare the thing that
actually matters: **the source compiles to a binary that passes the identical regression suite**,
and a `strings`/`diff` pass against the released binary turns up nothing beyond the differences
named above (the signature, the timestamp, the notarization ticket, and that one build-path
literal). Closing this gap fully — a deterministic, reproducible release pipeline — is future work,
not a claim made here.

---

## How to verify

1. **Turn Wi-Fi off. Dictate. Select and press ⌃V.** Both verbs work — transcription, cleanup,
   the dictionary, read-aloud, history. That is the architecture, not a mode.
2. **Watch the wire.** Give warble a deny-all rule set in Little Snitch and use it for a day:
   the only asks you'll ever see are `raw.githubusercontent.com` (the update check — park it by
   flipping **Install updates automatically** off), `github.com` if you accept an update (the
   dmg download), and, during Setup only, the hosts enumerated
   above. Or sample it live: `nettop -p $(pgrep -x warble)` while dictating shows loopback rows
   only (unless a scheduled update check happens to fire in that window). The scripted twin of
   this is docs/testing.md's Little Snitch silence test.
3. **Run the suite.** `sh scripts/regression.sh` from a checkout — every claim with a scripted
   twin, including the structural greps (the context module's zero networking symbols, the
   loopback-only proxy discipline, and this document's own tripwires — the `transparency`
   check fails the build if a disclosed mechanism disappears from this file, or if a
   known-overclaim phrase reappears anywhere in the docs).
4. **Read the log.** The `log stream` one-liner above, while you dictate.
5. **Audit the data.** `ls -leA ~/.warble` (owner-only permissions), `defaults read
   io.github.sethmed7.voz` (the settings table above — and nothing that looks like content),
   Dashboard ▸ Data & Privacy for the live size accounting, Export for the full history JSON.
6. **Check the shipped app, not just the repo.** `codesign -dv --verbose=2
   /Applications/warble.app` (Developer ID signature), `spctl -a -vv /Applications/warble.app`
   (notarization), and `strings /Applications/warble.app/Contents/MacOS/warble | grep -E
   'https?://'` — expect the loopback prefix (`http://127.0.0.1:`) and Setup's download hosts
   (github.com/k2-fsa releases, huggingface.co, bun.sh), and nothing else; the appcast URL lives
   in the plist, not the binary: `plutil -extract SUFeedURL raw
   /Applications/warble.app/Contents/Info.plist`.

*Corrections to this document are treated as bugs of the highest severity (product.md §4.9: one
overclaim forfeits the moat). If you find a hook, file, or destination not listed here, please
open an issue with the command that surfaced it.*
