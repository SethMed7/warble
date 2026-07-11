# warble roadmap

*Written 2026-07-11 from the verified Wispr Flow teardown
([docs/competitive/wispr-flow.md](docs/competitive/wispr-flow.md)) and its critic pass. The
product it executes: [docs/product.md](docs/product.md).*

**The shape of the plan:** the repo stays **private** while the product is polished to the public
bar; going open source *is* the launch, and it happens once — so it has to land. Every milestone
below ends shippable (a signed dmg Seth dogfoods daily). Sequence matters more than dates; a
milestone is a few focused weeks, not a quarter.

**Standing rule for every claim we ever publish:** measured end-to-end, primary-sourced, and
conceding rivals' real strengths. The trust position *is* the product (product.md §4.9).

---

## Where we are — 0.2.0 (shipped)

Rename complete (voz → warble), trill mark + cleaned icon/menu-bar glyph, real dashboard window,
warm Parakeet ASR (~0.08s engine time), Kokoro read-aloud with follow-along, on-device LLM polish,
learning dictionary, local history with replay, Sparkle updates, marketing media regenerated.

---

## 0.3 — "Never lose a word" (reliability core)

*The foundation every other promise stands on. Evidence: Wispr treats dictated words as unlosable
and users notice; "Transcript failed to load" is their documented weak spot; "it rewrote what I
said" is the sharpest cross-camp complaint against AI cleanup.*

- **Dictation recovery.** If the app dies, the paste fails, or transcription errors mid-session,
  the audio + partial transcript are recoverable from history. Wire the existing `~/.warble`
  recordings into an explicit *Recover* affordance.
- **Long-session hardening.** Define and test the max-hold story (Wispr caps at 20 min with a
  warning at 19). Decide warble's cap, warn before it, never truncate silently.
- **Cause-naming errors.** "Mic in use by another app," "mic disconnected," "engine still
  warming" — never a generic failure toast.
- **Cleanup levels + undo-polish.** None / Light / Medium / High mapped onto the existing
  deterministic-vs-LLM pipeline split, **verbatim-leaning default**, with a raw-transcript reveal
  per history item ("show what I actually said").
- **Honest numbers, measured.** Build the benchmark harness this milestone so every later claim
  is real: (a) **end-to-end latency** — key-release → paste event, cold and warm, vs Wispr's
  ~1.8s observed; (b) **WER** on a public corpus subset + a personal jargon corpus, published
  next to Wispr's ~97% independent number; (c) **idle footprint** — RAM/CPU with warm servers on
  and off (the critic is right that warm Parakeet + Kokoro may rival Wispr's 800MB — find out,
  publish whatever is true, and add a "warm engines" toggle if the number demands it).

**Exit:** a month of dogfood with zero lost dictations; the three benchmark numbers exist in
`docs/benchmarks.md` with reproduction steps.

## 0.4 — "The first five minutes" (onboarding)

*The acknowledged killer of indie menu-bar apps, and Wispr's strongest craft. Evidence: their 16-step
onboarding is the industry benchmark; their churn fix was first-dictation-in-your-own-apps; the
critic's catch — premium-engine download friction is the real local-app first-five-minutes killer.*

- **Sequential permission cards.** One permission per card, one-line "why," deep links into
  System Settings, grant-one-reveal-next — plus a post-macOS-update re-verify (silent
  Accessibility revocation is a documented support generator for Wispr).
- **Guaranteed first success.** Live mic-level meter first; then one sandboxed practice dictation
  with a deliberately messy sentence ("Umm, let's meet Friday at 3 — no, actually 4") showing the
  cleanup working; then — the part nobody else can do — **read-aloud demo in the same sandbox**
  (select this paragraph, press ⌃V). Both verbs land in minute one. Skippable, always.
- **End in the user's own app** within ~60 seconds: prompt a real dictation into Mail/Slack/the
  terminal.
- **Engine setup friction.** warble works instantly on Apple's engine — make the upgrade path
  honest and painless: size expectations up front, resumable downloads, progress that never
  lies, dictation usable *while* downloads run, and a "later" that never nags.
- **The listening contract.** Distinct start sound + the electric waveform + a visibly distinct
  processing state; hover the pill → shows the hotkey.

**Exit:** a fresh-Mac install (or fresh user account) reaches a successful real-app dictation and
one read-aloud inside five minutes with no verbal instructions from Seth.

## 0.5 — "Cheap parity" (ergonomics trio)

*Three loved Wispr features that are trivial locally, plus the proofreading loop that only warble
can build. Evidence: the product-features report's explicit "gaps warble could close cheaply."*

- **Snippets.** Spoken trigger phrase → local text expansion (signatures, addresses, canned
  replies). Fully local, managed in the dashboard.
- **"Press enter" auto-send.** Spoken at the end of a dictation, sends the message — huge for
  chat apps. Recognized only in the final position, off by default.
- **Multi-shortcut + mouse bindings.** Additional trigger combos and mouse-button push-to-talk —
  the RSI/accessibility audience warble should court binds dictation to a thumb button.
- **Dictate → read-back proofread.** One keystroke after a dictation reads the result back with
  the follow-along — the bidirectional loop as a *workflow*, not just two features. (Was already
  on the pre-teardown roadmap; the teardown confirms nobody else can copy it.)

**Exit:** all four in daily dogfood use; snippets and bindings editable in the dashboard.

## 0.6 — "Context, locally" (the scandal inverted)

*Context awareness is the one loved Wispr feature warble lacks — and their screenshot/keystroke
scandals make "context that never leaves your Mac" a positioning weapon. Evidence: privacy report +
sentiment report.*

- **Local-only context awareness.** Per-app tone/formatting (casual in Slack, formal in Mail,
  code-aware in terminals/editors) read via Accessibility, processed entirely on-device, **off by
  default**, explained in one plain sentence, excluded from password fields — and visibly
  inspectable: show the user exactly what context was read for any dictation.
- **Dashboard retention pass.** WPM percentile vs typists, "corrections cleaned for you," word
  counts in human units, streak heatmap, locally-rendered share cards, visible dictionary
  learning ("warble learned: Parakeet"). Wispr's stickiest surface, with zero telemetry.

**Exit:** context awareness demonstrably improves per-app output in dogfood while Little Snitch
shows nothing; the dashboard tells a week's story at a glance.

## 0.7 — "The trust dossier" (pre-public hardening)

*Everything the public moment will be judged on, built before the audience arrives. Evidence: the
Wensen Wu forensic piece is the template of the audit warble should invite — pass it in advance.*

- **The transparency doc.** What warble hooks and why (each API, each permission), exactly what
  `~/.warble` stores with sizes/caps/export/clear, what never happens (no network but the two
  disclosed calls), and how to verify each claim yourself.
- **Release integrity.** Signed + notarized (done) plus published checksums, and document the
  path toward reproducible builds.
- **`/vs/` comparison pages, drafted.** wispr-flow (scrupulously fair, primary-sourced, conceding
  accuracy/onboarding/ZDR), superwhisper, voiceink, handy, and "why not Apple's built-ins."
- **Wispr import tool.** Dictionary (and optionally history) from Wispr's local SQLite — the
  concrete switch path.
- **Repo hygiene for open-sourcing.** History audit (no secrets/paths/keys — strip or squash),
  CONTRIBUTING.md, issue templates, license headers, CI for the headless smoke tests.
- **SpeechAnalyzer evaluation.** Apple's on-device API (macOS 26) is available to every
  competitor — absorb it: evaluate as another engine in warble's fallback chain (it may beat
  whisper.cpp as the zero-download tier and partially neutralizes the Apple risk).

**Exit:** an adversarial stranger armed with Little Snitch, `strings`, and the transparency doc
finds nothing undisclosed; the repo could be flipped public tomorrow without embarrassment.

## 1.0 — Public (the launch, once)

**The gate — flip public only when all of these are true:**

1. 0.3–0.7 exit criteria all met (no partial credit).
2. Benchmarks published with reproduction steps (latency end-to-end, WER, idle footprint).
3. Onboarding passes the fresh-Mac five-minute test with a non-Seth human.
4. The transparency doc + comparison pages are live and every claim primary-sourced.
5. Repo history audited; README, media, and docs coherent (no voz ghosts).
6. Sustainability statement published (product.md §8; Sponsors enabled).
7. A month of zero-data-loss dogfood on the release build.

**The moment itself:**

- Flip `SethMed7/warble` public; releases public; **Homebrew cask** PR.
- **Show HN:** "the open-source Wispr Flow that also reads aloud" — with the side-by-side latency
  video (both apps, same sentence) as the money asset.
- r/macapps post; reach out to the reviewers who cover superwhisper/VoiceInk; a deliberate
  RSI/accessibility community motion (their forums, plain language, mouse-button PTT as the hook).
- Comparison pages indexed; "is wispr flow safe" query stream starts working.

## Someday / maybe (explicitly parked)

- Non-macOS shells over `core/` (the code stays portable; the commitment stays unmade).
- Command-mode voice editing (revisit only after the core gaps; Wispr's own version is still
  experimental and paid).
- EU/GDPR-angled positioning page (the architecture already answers it; write it when a European
  audience materializes).
- Multilingual first-class support (whisper.cpp fallback + honesty until then).

## Standing risks being managed

| Risk | Standing answer |
| --- | --- |
| Wispr ships read-aloud | Make bidirectionality synonymous with warble *now*; theirs would still be cloud TTS |
| Apple ships category-killing dictation | Absorb SpeechAnalyzer as an engine; win on any-app polish, dictionary, dashboard, iteration speed |
| "Handy but Mac-only" | Bidirectional + dictionary + dashboard + Wispr-grade craft; never lead with "free local dictation" alone |
| Solo-dev capacity | Milestones stay small and shippable; responsiveness is itself the differentiator — while shipping continues |
| Overclaiming | Product.md §4.9; every public number measured end-to-end with reproduction steps |
