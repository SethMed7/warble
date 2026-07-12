# Apple SpeechAnalyzer — evaluation (ROADMAP 0.7)

*Written 2026-07-12. The roadmap item: "SpeechAnalyzer evaluation — Apple's on-device API (macOS 26)
is available to every competitor; absorb it as warble's zero-download tier instead of being disrupted
by it." This is the evidence, the design, and the honest limits of what could be measured. Rules:
[product.md](product.md) §4.9 — measured end-to-end, primary-sourced, no fabricated numbers.*

---

## Verdict

**The SDK probe succeeded, so warble ships a real engine, not a stub.** Apple's `SpeechAnalyzer` /
`SpeechTranscriber` (Speech framework, macOS 26) is exposed to the current toolchain, compiles under
warble's `.macOS(.v13)` deployment target behind `@available(macOS 26, *)` guards, and is wired into
the transcription chain as an availability-gated tier named **`Apple SpeechAnalyzer`**, sitting
**below whisper.cpp and above the legacy Apple SFSpeechRecognizer floor**.

**But it is not automatically "zero-download."** On the evaluation machine the on-device transcription
*assets* for `en-US` are **not installed** — the OS reports the module as `supported` (downloadable),
not `installed`, and calling analysis without the assets **traps**. warble therefore treats a
supported-but-not-installed engine as *absent* (the chain falls through to the always-present Apple
floor) and **never** triggers the system asset download from the paste path. That is the whole nuance
the roadmap's "zero-download tier" framing has to survive contact with: it is zero-download *for users
who already have the SpeechAnalyzer assets*, and an honest, consented install otherwise — never a
silent one.

## Environment

| | |
| --- | --- |
| OS | macOS 26.5.1 (build 25F80) |
| Toolchain | Apple Swift 6.2.4 (swiftlang-6.2.4.1.4), target `arm64-apple-macosx26.0` |
| SDK | MacOSX 26.2 (`Speech.framework`, user-module-version 3510.3.1) |
| Deployment target | `.macOS(.v13)` (Package.swift) — so every SpeechAnalyzer symbol must be `@available(macOS 26, *)`-gated |

## The probe — what the toolchain actually exposes

`Speech.framework`'s macOS swiftinterface declares the full surface, each annotated
`@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)` (unavailable on tvOS/watchOS):

- `actor SpeechAnalyzer` — `init(modules:options:)`, `analyzeSequence(from: AVAudioFile) -> CMTime?`,
  `finalizeAndFinish(through:)`, `cancelAndFinishNow()`, `finalizeAndFinishThroughEndOfInput()`.
- `class SpeechTranscriber : SpeechModule, LocaleDependentSpeechModule` — `init(locale:preset:)` with
  presets `.transcription`, `.progressiveTranscription`, …; `static var isAvailable: Bool`;
  `static var supportedLocales`/`installedLocales` (async); `results` (an `AsyncSequence` of
  `Result` whose `text` is an `AttributedString`).
- `class DictationTranscriber` — the dictation-tuned sibling (presets `.shortDictation`,
  `.longDictation`; content hints incl. `.atypicalSpeech` for accessibility). No `isAvailable` flag.
- `class AssetInventory` — `status(forModules:) -> Status` (`unsupported < supported < downloading <
  installed`), `assetInstallationRequest(supporting:) -> AssetInstallationRequest?`, locale
  reservation (`reserve`/`release`, `maximumReservedLocales == 5`).
- `class AssetInstallationRequest : ProgressReporting` — the download handle (system-managed).

A small standalone `swiftc` program (no app bundle) linked and ran against this SDK, confirming the
symbols resolve and the metadata queries work at runtime. Observed, verbatim:

```
SpeechTranscriber.isAvailable: true
ST supportedLocales count: 30
ST installedLocales: ["en-ZA","en-CA","en-GB","en-IE","en-US","en-SG","en-AU","en-NZ","en-IN"]
current locale: en-US
ST supportedLocale(equivalentTo current): en-US
DT supportedLocales count: 54
DT installedLocales: ["en-US"]

AssetInventory.status(SpeechTranscriber@en-US): supported        # <- NOT .installed
AssetInventory.status(DictationTranscriber@en-US): supported     # <- NOT .installed
ST assetInstallationRequest(supporting:): NON-NIL (download required)
DT assetInstallationRequest(supporting:): NON-NIL (download required)
maximumReservedLocales: 5
reservedLocales: ["en-US"]
```

And the load-bearing negative: calling `SpeechAnalyzer.analyzeSequence(from:)` with the assets in the
`.supported` (not `.installed`) state **crashes** — a `SIGTRAP` inside `analyzeSequence(from:)`:

```
"signal":"SIGTRAP"  frame: SpeechAnalyzer.analyzeSequence(from:)
```

### The finding that drives the design

`SpeechTranscriber.installedLocales` **listing `en-US` is necessary but not sufficient.** The
authoritative gate is `AssetInventory.status(forModules:) == .installed`. Here `installedLocales`
contains `en-US` yet the module's status is only `.supported`, and analysis traps. So warble's
availability check must be the *asset status*, not the locale list — anything looser would hand audio
to an analyzer that crashes, or (worse) trigger a hidden multi-hundred-MB download.

## The integration

All in [`apps/macos/Sources/Dictate/Transcriber.swift`](../apps/macos/Sources/Dictate/Transcriber.swift):

1. **`SpeechAnalyzerTranscriber`** — a `Transcriber` conformer, `@available(macOS 26, *)`. Its
   `transcribe` does one file-mode pass: build `SpeechTranscriber(locale:preset:.transcription)` for
   the current locale (via `supportedLocale(equivalentTo:)`), attach it to a `SpeechAnalyzer`, feed
   the WAV with `analyzeSequence(from:)` while draining `transcriber.results` concurrently, then
   `finalizeAndFinish(through:)`. Bounded by the same `timeout` every engine honors (a race-free
   result box lets the timeout and the analyze task hand a value across threads, first-writer-wins),
   so a wedged analyzer can never hang the paste path. Any error → `nil` → the chain falls through.

2. **The availability gate.** `isAvailable()` is `true` **only** when `AssetInventory.status ==
   .installed` for the current locale — memoized per process via a bounded sync-over-async bridge
   whose work runs off the caller's thread (validated safe from the main thread, ~60 ms once). This
   is the honesty guarantee: warble never analyzes without the assets, and never kicks off the
   system download from a dictation. If assets are merely `.supported`, the engine is *absent*.

3. **Chain placement.** `run()` appends it after whisper.cpp and before the Apple floor, guarded by
   `if #available(macOS 26, *)`. The order is centralized in a pure `chainOrder(...)` function — the
   single source of truth `run()` and `activeEngineName()` agree on — so the placement is
   unit-testable with no engine installed (`SpeechAnalyzerTests`). SpeechAnalyzer sits above the
   legacy floor — not on a measured accuracy win (none was taken; the assets were absent) but
   because it is Apple's newer on-device transcription model (macOS 26) and needs no third-party
   download, a default preference that is safe because the chain falls through to the floor if it
   ever underperforms — and below whisper.cpp (the conservative default until a measured WER says
   otherwise — see [benchmarks.md](benchmarks.md) §4).

4. **Name + seams.** `activeEngineName()` reports `Apple SpeechAnalyzer` (distinct from the legacy
   `Apple Speech` floor). The bench seam `WARBLE_FORCE_ENGINE=speechanalyzer` pins the chain to it
   alone (empty chain → clean failure when assets are absent — never a silent Apple fallback that
   would mislabel a number). `engine-missing` (the debug fault that forces the floor) suppresses it
   like any premium tier, so "engine-missing forces the Apple floor" stays true even on a Mac where
   the SpeechAnalyzer assets *are* installed.

5. **The download, surfaced honestly.** A required asset install is never silent. Today it manifests
   as the engine being *absent* (falls through to the floor, which works); the asset requirement is
   documented (README Engines section, [benchmarks.md](benchmarks.md) §4, here). Wiring a dedicated
   Setup card that installs the SpeechAnalyzer locale asset on explicit consent — the same
   size-first, consent-first idiom as the Parakeet/Kokoro/LLM installers — is the natural next step
   and is noted as follow-up; this evaluation deliberately stops short of triggering any download.

## DictationTranscriber vs. SpeechTranscriber

Both are locale-dependent SpeechAnalyzer modules; both were `.supported`-not-`.installed` here.
`SpeechTranscriber` is the one the roadmap names, the one with a public `isAvailable`, and Apple's
general-purpose transcription model — so it is the integrated engine. `DictationTranscriber` (with
`.atypicalSpeech`/`.farField` content hints) is a compelling future addition specifically for the
RSI/accessibility audience warble courts, and the engine is structured so swapping or adding it is a
localized change. Called out as follow-up, not built here.

## What is proven vs. by-hand

- **Proven headlessly** (in `scripts/regression.sh`, engine-free): the tier's name wiring
  (`WARBLE_FORCE_ENGINE=speechanalyzer` → `Apple SpeechAnalyzer`), the no-silent-fallback contract
  when forced-but-absent, `engine-missing` still forcing the floor, and the chain-order resolution
  (`SpeechAnalyzerTests` over the pure `chainOrder` — SpeechAnalyzer below whisper, above the
  always-present floor). Tolerant by construction: present on a macOS 26 machine with the assets,
  gracefully absent everywhere else — the same idiom as whisper.cpp's absence in the benchmarks.
- **By-hand** (needs the macOS 26 assets installed, [testing.md](testing.md)): the live transcription
  path — force the engine over a real clip once the assets are present and confirm real text, then
  the real WER/latency numbers via the unchanged bench harness (benchmarks.md §4). The evaluation
  machine's assets were `.supported`, not `.installed`, and no download was triggered to fake a
  number.
