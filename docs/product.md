# warble — product definition

*The canon for what warble is, who it serves, and what it will never do. Written 2026-07-11,
grounded in the verified competitive teardown ([competitive/wispr-flow.md](competitive/wispr-flow.md)).
The roadmap that executes this definition: [../ROADMAP.md](../ROADMAP.md).*

---

## 1. What warble is

warble is **the voice layer for your Mac — speak to type, select to hear.** It is the only voice
tool that works in both directions, and the only one you can verify: 100% on-device, free, and
(once the polish bar is met) open source under MIT. No account, no cloud, no telemetry, no word
meter. Turn off Wi-Fi and it still works.

The one-sentence position: **it talks back — and it never talks to a server.**

warble is an *instrument*, not a lifestyle product: a quiet black surface with a single
electric-blue signal that moves only when voice moves. The craft bar is Wispr Flow — the category
leader whose polish defines user expectations — while the architecture is everything Wispr cannot
be: local, verifiable, unmetered.

## 2. Who it's for

1. **Keyboard professionals on a Mac** — developers, writers, operators who live in editors,
   terminals, Slack, and mail, and who dictate because it's faster (and read aloud because ears
   catch what eyes skim).
2. **People who check** — the r/macapps / Hacker News / Little-Snitch audience that actively
   searches "is Wispr Flow safe." They are few but they write the reviews everyone else reads.
3. **Professionals whose data can't leave** — law, medicine, finance, journalism. Their answer
   isn't a compliance PDF; it's architecture: the data never leaves the machine.
4. **RSI and accessibility users** — for whom voice isn't a productivity trick but the primary
   input, and read-back is the primary proofread.
5. **The Wispr free-cap refugee** — Wispr's own retention data guarantees habituated free users
   hit the 2,000-word weekly cap right as the habit forms. That cliff is warble's top-of-funnel.

Deliberately *not* the target: the 104-language mass market, enterprise procurement, and anyone
who wants a notes app.

## 3. The two verbs

- **Dictate (voice → text).** Hold **Fn** (or double-tap for hands-free), talk, release. On-device
  transcription (Parakeet → whisper.cpp → Apple), deterministic cleanup, optional on-device LLM
  polish. It learns your words from corrections and spoken spelling, and never loses a dictation.
- **Read aloud (text → voice).** Select anywhere, press **⌃V**. Kokoro neural voices with a
  word-by-word follow-along panel; the same dictionary teaches pronunciation.

Bidirectionality is the uncontested wedge: Wispr Flow and the entire free-local pack (Handy,
VoiceInk, superwhisper, Hex) are dictation-only. It leads every description of the product, and
the two halves reinforce each other — the proofreading loop (speak it, hear it back) is a feature
neither a dictation app nor a TTS app can offer alone.

## 4. Principles (the constitution)

1. **100% on-device, forever.** No cloud mode at any tier, ever. This is architecture, not policy.
2. **No account, ever. No telemetry, ever.** Success is measured in external signals (stars,
   downloads, reviews), never in shipped instrumentation.
3. **Free + MIT.** No meter, no trial cliff, no lifetime-unlock. Sustainability comes from
   sponsorship and reputation, not gates (see §8).
4. **Verbatim by default, polish on request.** The words are the user's. Anything that rewrites
   rather than transcribes must be opted into, visible, and undoable to the raw transcript.
5. **Never override user intent.** Nothing re-enables itself, re-adds itself to Login Items, or
   nags. A mode turned off registers nothing and asks for nothing. (Wispr's most resented behavior
   is the inverse; it's a standing warning.)
6. **Transient by default.** No persistent pill squatting on the screen. Surfaces appear when
   voice is live and vanish when it isn't. Pinning is an option, never the default.
7. **Motion is the signal.** One accent, dark surfaces, the waveform moves only when the mic is
   hot or audio plays. (The full design law: [../DESIGN.md](../DESIGN.md).)
8. **Local data is also a privacy surface.** History and recordings live under `~/.warble`,
   owner-only, visible in the dashboard, with export/clear and honest size accounting. Wispr's
   694MB silent hoard is the cautionary tale — warble hoards nothing silently.
9. **Precision in every public claim.** Comparisons quote the competitor's own documentation,
   measure end-to-end (never engine-time vs their round-trip), and concede rivals' real strengths.
   One overclaim forfeits the trust moat; the trust moat is the business.
10. **Dictated words are unlosable.** A crash, a mis-targeted paste, or a failed transcription
    must never mean re-saying it.

## 5. Named surfaces

Named things feel designed; these are the official names (used in code comments, docs, and UI):

| Surface | Name |
| --- | --- |
| The dictation capsule (bottom-center, waveform) | **the pill** |
| The read-along window | **the follow-along panel** |
| The learned words + pronunciations | **the dictionary** |
| The stats/history window | **the dashboard** |
| The menu-bar glyph | **the trill** (the mark itself) |
| The premium-engine installer | **Setup** ("Set up better engines…") |

## 6. Non-goals

Each of these is a decision, not an omission:

- **No cloud fallback, no hybrid mode.** Even "just for accuracy." It would delete the position.
- **No account system** — nothing to log into, nothing to breach.
- **No multilingual arms race.** Wispr's 104-language auto-detect moat is conceded. warble is the
  best *English* voice layer on-device; whisper.cpp remains the multilingual fallback, stated
  honestly in every comparison.
- **No Windows/iOS/Android (for now).** Mac-first is a respected position in this niche; the
  portable `core/` keeps the door open without committing to it.
- **No enterprise compliance machinery** (SOC 2, BAA, SSO, admin consoles). The regulated buyer's
  answer is architectural.
- **No notes app / scratchpad.** rotli exists; a voice layer that becomes a notes app is how a
  solo project loses focus.
- **No notification-driven engagement.** Teaching happens in the dashboard, quietly.
- **No persistent on-screen UI by default** (see principle 6).

## 7. Why not X — the honest answers

- **Apple Dictation?** Free and on-device, but raw: no filler removal, no learned dictionary that
  syncs into a terminal, no cleanup levels, no per-app polish, and no ecosystem of care around the
  transcript. warble is what dictation becomes when someone sweats it.
- **Apple Spoken Content (select + hotkey read-aloud)?** Exists, and honesty requires saying so.
  warble's read-aloud differs in kind: neural Kokoro voices, a follow-along panel that tracks word
  by word, queued selections, collapse-to-player, and the same dictionary driving pronunciation of
  your names and jargon. Apple reads text at you; warble follows along with you.
- **Handy (~26k stars, MIT, same Parakeet)?** The strongest free-local rival — and on raw engine,
  parity. warble's answer is the layer above the engine: bidirectional voice, the learning
  dictionary, the local dashboard, and design at Wispr's craft level rather than utility level.
  If warble ever reads as "Handy but Mac-only," the wedge is gone (see roadmap risk items).
- **superwhisper / VoiceInk / MacWhisper?** Local dictation utilities with real followings and
  real gaps (developer responsiveness, polish, no read-aloud). warble competes on craft +
  bidirectionality, and never disparages — these are allies against the cloud default.
- **Wispr Flow?** The best onboarding and accuracy in the category, and an architecture that
  cannot work offline, requires an account, trains on data unless Privacy Mode is flipped on, and
  meters free usage weekly. The comparison page quotes only their own documentation.

## 8. Sustainability

"Free from a solo dev" triggers abandonment fear in exactly this niche, so the answer is stated
rather than implied: warble has **no business model to die** — no servers to fund, no investors to
satisfy, no acquisition that can turn it off. The code is MIT (public at the 1.0 gate); the models
are open weights cached locally; a signed release keeps working forever without any company
existing. Optional GitHub Sponsors funds the developer, not the product's survival. The visible
heartbeat is the changelog: in this niche, reviewers weight developer responsiveness heavily, and
a solo dev who ships and answers is a feature — while the shipping continues.

## 9. What winning looks like

warble has zero telemetry, so success is defined only in externally observable signals, measured
at +90 days after the public 1.0 launch:

- **1,000+ GitHub stars** (the Show HN survives the "Handy but Mac-only" test).
- **Homebrew cask** merged and counting installs in brew analytics.
- **The comparison pages rank** for "wispr flow alternative" / "is wispr flow safe" queries.
- **Independent reviews exist** (r/macapps, YouTube) that repeat the bidirectional + verifiable
  framing unprompted — the message survived contact.
- **Zero broken-trust incidents:** no claim retracted, no permission surprise, no data-loss report
  unanswered.

Until the public gate, "winning" is simpler: Seth's own daily use never loses a word, and each
milestone's exit criteria (see [ROADMAP.md](../ROADMAP.md)) are met honestly.
