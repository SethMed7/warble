# warble vs. Apple's built-ins

*DRAFT — staged for warble's public launch, not yet linked from anywhere. See
[docs/vs/README.md](README.md) for what "draft" means here. Every Apple fact below is cited to
Apple's own support documentation (support.apple.com, 2026-07); the latency/WER numbers for
"Apple Speech" are warble's own measured numbers, gathered by literally running warble's fallback
engine, which *is* Apple's on-device recognizer — the most directly comparable numbers on any page
in this set, because they came from the same harness and the same fixture clips/corpus (WER scored
both engines in one pass; latency used two separate runs at different N — see the note below the
table).*

Every Mac already does both of warble's verbs. **System Settings → Keyboard → Dictation** turns
speech into text; **System Settings → Accessibility → Spoken Content** ("Speak selection," default
shortcut Option-Esc) turns selected text back into speech. Free, on-device by default on Apple
Silicon, zero download, zero install. This is the one comparison on this page where the honest
answer to "why not just use what's already there" has to be depth, not existence — because Apple
already has both verbs.

## What they do better

- **Already on every Mac, free, forever.** No download, no permission gauntlet beyond the OS's own
  prompts, no app to keep updated. For most people most of the time, this is genuinely the right
  first thing to try.
- **Mature, audited accessibility engineering.** Spoken Content isn't a bolted-on feature — it's
  part of the same system that drives VoiceOver, Braille-display support, and highlighting that
  tracks word-by-word or sentence-by-sentence, with a real onscreen controller for rate/skip. This
  is Apple's actual accessibility investment, not a checkbox.
- **No timeout on dictation length.** Apple's own docs: *"You can dictate text of any length without
  a timeout"* — it only stops after 30 seconds of silence, not after any fixed duration. warble caps
  a single hold at 20 minutes (ROADMAP 0.3, matching the category norm); Apple's Dictation has no
  such ceiling.
- **Dictation is at least sometimes genuinely on-device.** Apple's own Keyboard settings let you
  check *"whether your voice inputs and transcripts for general text Dictation... are processed on
  your device and not sent to Siri servers."* That's a real, checkable claim — not every dictation
  vendor offers you that switch to inspect at all.
- **It's fast, too.** This isn't a hedge — warble's own harness measured Apple's on-device engine at
  49.4 ms median (see the table below). Apple's floor tier is not a slow fallback; it's a
  legitimately quick, zero-setup option.

## The honest comparison table

| | Apple Dictation + Spoken Content | warble |
| --- | --- | --- |
| License | Proprietary, part of macOS — no source available | MIT (open source at public launch) |
| Price | Free, bundled with every Mac | Free, no tier, nothing to unlock |
| Offline | Conditional — Apple's own docs say you can check Keyboard Settings for *"whether your voice inputs... are processed on your device and not sent to Siri servers,"* which implies it isn't guaranteed in every configuration | Yes, always, unconditionally — no cloud code path exists in the app at all |
| Accounts | None required for the features themselves | None |
| Telemetry | Apple's docs describe an opt-in program: users "may review a sample of stored audio" if they opt into sharing, and can delete interaction history; framed as opt-in, not default-on | None, ever |
| Read aloud | **Yes** — Spoken Content / Speak Selection, system voices, word/sentence highlighting, an onscreen rate/skip controller | Kokoro-82M neural voices, select + ⌃V, word-by-word follow-along panel, plus the dictate → read-back proofreading loop |
| Learning dictionary | No user-facing learned-word dictionary that follows corrections into every app — Dictation transcribes what it hears, with no cleanup levels or per-app tone shaping | Yes — learns from corrections and spoken spelling, local-only, shapes cleanup per app |
| Latency (warm) | **49.4 ms median / 141.7 ms p95** (N=5) — measured by warble's own harness with the engine pinned to Apple's recognizer (`WARBLE_FORCE_ENGINE=apple`); same harness and fixture clip as warble's own number below, but a separate run at a different N (see the note below the table) | 64.6 ms median / 75.9 ms p95 (N=10, warm Parakeet) — Apple's floor engine is genuinely competitive on raw speed |
| WER | **11.9%** (38 errors: 28 substitutions, 10 deletions) on the 40-clip synthetic corpus | 0.9% (3 errors, all substitutions) on the same corpus, same run — see the note below |

**A note on these numbers — the most directly comparable pair on any `/vs/` page warble publishes:**
both rows above came from the exact same harness and the same fixture clip/corpus, with only the
`WARBLE_FORCE_ENGINE` seam changed — this is the one competitor comparison where warble isn't
measuring itself one way and a rival another with different tooling. That said, the two rows were
not produced identically: **WER** scores every installed engine, Apple's and Parakeet's, in one
`wer-corpus.sh` pass over the same corpus — genuinely the same run. **Latency** did not — Apple's
number came from `latency.sh --engine apple --no-cold --runs 5` and Parakeet's from
`latency.sh --runs 10`, two separate invocations at different N, same harness and clip but not one
run. The corpus caveat still applies to both sides equally: the WER corpus is **studio-clean
synthetic speech** (macOS `say`, two voices × two rates), which structurally underestimates
real-world error for every engine tested — the *relative* gap between Apple's floor and Parakeet is
meaningful, the *absolute* numbers are a ceiling, not a promise. Latency is engine time only, not a
full release-to-text-visible measurement for either engine. Full method, every number, and
reproduction commands: [docs/benchmarks.md](../benchmarks.md) §1–§2.

## Who should pick them

If you dictate occasionally rather than constantly, want zero setup and zero apps to manage, need
mature VoiceOver-grade accessibility tooling that's been engineered and audited for years, or you're
on a Mac where installing anything else isn't an option — Apple's built-ins are the right answer,
and should honestly be the first thing anyone in this whole category tries before reaching for a
third-party app, warble included.

## Who should pick warble

If dictation is a daily-driver habit rather than an occasional convenience, you want a learning
dictionary that actually shapes what lands in your terminal and editor, you want cleanup levels with
a raw-transcript reveal instead of raw ASR output, or you want read-aloud that *follows along* with
you word by word rather than just speaking at you — Apple gives you both verbs, and warble is what
both verbs become when someone spends a project sweating the details on top of them.

## Sources

- [support.apple.com — Use Dictation](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac) —
  on-device vs. Siri-server processing, the 30-second silence timeout, no length cap
- [support.apple.com — Have your Mac speak text that's on the screen](https://support.apple.com/guide/mac-help/have-your-mac-speak-text-thats-on-the-screen-mh27448/mac) —
  Speak Selection, the default Option-Esc shortcut, highlighting options
- [support.apple.com — Change Spoken Content preferences](https://support.apple.com/guide/mac-help/change-spoken-content-preferences-spch638/mac) —
  system voices, rate control, highlight customization
- [docs/benchmarks.md](../benchmarks.md) §1–§2 — the "Apple Speech, forced" and "Parakeet" rows,
  measured on the same harness and corpus (WER: same run for both engines; latency: separate runs
  at different N — see the note above)
