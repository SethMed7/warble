# warble vs. Wispr Flow

*DRAFT — staged for warble's public launch, not yet linked from anywhere. See
[docs/vs/README.md](README.md) for what "draft" means here. Grounded in the verified teardown at
[docs/competitive/wispr-flow.md](../competitive/wispr-flow.md) and its full research appendix
([wispr-flow-research.md](../competitive/wispr-flow-research.md)) — this page cites that record
rather than re-deriving it, and nothing here goes further than what it verified.*

Wispr Flow is the category leader for a reason. This page says so first, on purpose: a comparison
page that only flatters itself isn't worth reading, and product.md §4.9 — warble's own constitution
— says one exaggerated claim about a competitor forfeits the whole trust position. Everything below
is dated 2026-07, cited to Wispr's own documentation or the fact-checked record linked above.

## What they do better

- **The best onboarding in the category.** Sequential permission cards, a live mic test, a
  sandboxed practice dictation that guarantees your first try works — 16 steps, and it's the
  acknowledged industry benchmark. warble's own onboarding (ROADMAP 0.4) was built studying theirs.
- **104 languages, auto-detected per dictation.** Roughly 60% of Wispr's own dictation volume is
  non-English. warble concedes this deliberately — it's English-first, with whisper.cpp as an
  honest multilingual fallback, not a competing claim.
- **A real zero-data-retention mode.** With Privacy Mode on *and* Private Cloud Sync off, Wispr says
  "audio and transcripts are processed in real time and discarded after each request" — genuinely
  real, and the default for their Enterprise/BAA customers.
- **A clean, current SOC 2 Type I.** After 2026's industry-wide Delve audit-mill scandal (which
  implicated their original certification), Wispr re-engaged A-LIGN and holds a clean **SOC 2 Type I
  (Security scope, April 2026)** — Type II is still in its observation period. That's real, and it's
  the honest current state, not the discredited one.
- **A funded team shipping fast.** ~50 people, reported 40%+ month-over-month growth, monthly
  releases, Command Mode voice-editing already live (paid, experimental). warble is a solo project;
  the roadmap says so.
- **Accuracy, independently measured.** Third parties report ~97% accuracy. warble has not measured
  a WER number on the same corpus with the same method — see the table below for why that number
  can't sit next to warble's without a caveat.

## The honest comparison table

| | Wispr Flow | warble |
| --- | --- | --- |
| License | Closed source, proprietary | MIT (open source at public launch) |
| Price | $15/mo or $144/yr; free tier capped at 2,000 words/week (desktop), 1,000/week (iPhone) | Free, no cap, no tier |
| Offline | No. Their own data-controls page: *"Transcription always occurs on the cloud. This is the best way for us to provide accurate, low latency transcription."* No offline mode at any price. | Yes — 100% on-device; works with Wi-Fi off |
| Accounts | Required (Google/Apple/Microsoft/SSO/email sign-in) | None |
| Telemetry | Product analytics + session-replay tooling identified in binary/log forensics of the app (PostHog, Sentry, Segment, Datadog, Google Analytics); dictation data may be used to evaluate/train Wispr's models **unless Privacy Mode is turned on (off by default)** | None, ever |
| Read aloud | None, anywhere in the product or its docs | Kokoro-82M neural voices, select + ⌃V, word-by-word follow-along panel |
| Learning dictionary | Yes — auto-learns from corrections, syncs across devices | Yes — learns from corrections and spoken spelling, local-only (no sync needed on one device) |
| Latency (warm) | Claimed p99 < 700 ms; independently observed ~1.8 s real-world round trip | ~65 ms median engine time (warm Parakeet), + an estimated ~20–60 ms for legs the harness can't reach — see the note below |
| WER | ~97% accuracy, independently reported (method not published by warble; see sources) | 0.9% WER (Parakeet) on a 40-clip synthetic corpus — see the note below |

**A note on the two rows above, because product.md §4.9 requires it right here and not just once at
the bottom:** warble's latency figure is its own paste-path harness timing (WAV → transcription →
cleanup → paste-ready string) over a fixture clip, plus an *estimated* allowance for the legs the
harness can't reach (key-up handling, WAV finalize, the paste event itself) — it is **not** a
full release-of-key-to-text-visible measurement, and it is **not** measured the same way as Wispr's
independently-observed 1.8 s round trip. Similarly, warble's 0.9% WER is scored on **studio-clean,
disfluency-free synthetic speech** (macOS `say`, two voices × two rates) — a corpus that
structurally underestimates real-world error for every engine tested, warble's included — and it
is **not comparable** to Wispr's independently-measured ~97% figure, which used a different corpus
and a different method entirely. Full method, caveats, and reproduction commands:
[docs/benchmarks.md](../benchmarks.md).

### Their record, precisely — not more, not less

A comparison this central to warble's identity has to get Wispr's actual incident record right, so
here it is at the qualifiers the fact-checked record actually supports (see
[wispr-flow.md §Risks item 6](../competitive/wispr-flow.md)): a late-2025 incident, reported by an
**anonymous** user who found the app uploading image data of the active window, led to that user
being banned; Wispr's CTO later apologized publicly after the backlash and reworked what's
captured. A later, independent forensic review (Wensen Wu, April 2026, app v1.4.752) documented an
always-on system-wide keystroke tap and extensive undisclosed app/URL logging — but its
**screenshot-BLOB column was not populated**, so the proven record is keystroke/URL/accessibility-
tree scope, not continuous screenshotting, and this page doesn't claim otherwise. Their original
SOC 2/ISO certifications were produced through the now-discredited Delve pipeline; they've since
earned the clean SOC 2 Type I noted above. None of this makes Wispr Flow unsafe to use — it means
their trust model is "believe the policy," and the record shows moments where policy and practice
diverged. warble's trust model is "read the code, turn off Wi-Fi, watch it still work."

## Who should pick them

If you dictate in more than one language regularly, want the single most polished onboarding
experience in the category, need SSO/admin dashboards/enforced compliance for a team, or want voice
editing (Command Mode) today rather than on warble's roadmap — Wispr Flow is the better tool for
you, honestly. A funded team shipping monthly will out-feature a solo project for a long time.

## Who should pick warble

If your dictation is mostly English, you want to *verify* privacy instead of trust a policy, you
work with text that shouldn't leave your machine (code, legal drafts, clinical notes, unpublished
writing), you've hit Wispr's 2,000-word weekly free cap right as the habit formed, or you want the
one thing no dictation app in this category offers — reading text back to you, in the same
follow-along voice, closing the loop on what you just dictated — warble is built for you.

## Sources

- [wisprflow.ai/data-controls](https://wisprflow.ai/data-controls) — "Transcription always occurs
  on the cloud"; Privacy Mode / ZDR mechanics
- [wisprflow.ai/pricing](https://wisprflow.ai/pricing) — $15/mo, $144/yr, free-tier word caps
- [docs.wisprflow.ai](https://docs.wisprflow.ai) — plans, security/compliance FAQ
- [wensenwu.com/thoughts/wispr-flow-investigation](https://www.wensenwu.com/thoughts/wispr-flow-investigation) —
  the April 2026 forensic record (keystroke tap, app/URL logging, unpopulated screenshot BLOB)
- [docs/competitive/wispr-flow.md](../competitive/wispr-flow.md) and
  [wispr-flow-research.md](../competitive/wispr-flow-research.md) — the full verified teardown this
  page draws from, including every fact-check correction applied
- [docs/benchmarks.md](../benchmarks.md) — warble's own latency/WER numbers, method, and caveats
