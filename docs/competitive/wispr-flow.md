# warble vs. Wispr Flow — Competitive Strategy
*July 2026. Grounded in six verified specialist teardowns; fact-check corrections applied throughout.*

---

## 1. Executive summary

Wispr Flow is the category leader: $81M raised (with a reported ~$260M Series B at ~$2B in progress, not confirmed closed), ~50 people, 40% MoM growth, 80% six-month retention, and a genuinely excellent product experience built on an architecture that cannot work offline. Every dictation — plus nearby screen text, app/URL metadata, and code file names — leaves the user's machine for Baseten, OpenAI, Anthropic, and Cerebras; their own docs say "Transcription always occurs on the cloud." Their trust record is strained: a late-2025 incident where they banned the anonymous user who found undisclosed active-window uploads (CTO later apologized), a March 2026 audit-mill scandal that forced a re-certification, and an April 2026 forensic investigation documenting an always-on keystroke tap, 1,688 app/URL log events in 30 hours, and a 694MB silent local data hoard. The mass market has demonstrably not punished any of this — growth continued through every incident — but a well-defined, high-word-of-mouth niche (developers, r/macapps, regulated professionals, EU users) cares intensely and actively searches "is Wispr Flow safe." warble cannot out-feature $81M and should not try; it wins by construction on four axes Wispr cannot copy without rearchitecting: 100% on-device (verifiable, not promised), free and MIT-licensed, ~0.08s warm latency vs their ~1.8s observed round trip, and bidirectional voice — read-aloud exists nowhere in Wispr's product or roadmap. The free-local genre is now crowded (Handy at ~26k stars, VoiceInk, Hex, superwhisper), so "free + local" alone is not a position; bidirectionality, the learning dictionary, the local dashboard, and Wispr-grade polish are what separate warble from that pack. warble's biggest real risks are its own first five minutes — Wispr's onboarding is the acknowledged bar, and indie apps die at the macOS permissions gauntlet — and English-centric models in a market where 60% of Wispr's dictations are non-English. The strategy: copy Wispr's first five minutes, structurally reject everything users revolt against (account, cloud, persistent pill, word-cap cliff), and lead with the one sentence no competitor can say: it talks back, and it never talks to a server. Precision is the moat — one overclaim about Wispr's behavior forfeits the entire credibility advantage. Concede the 104-language mass market and enterprise compliance; own the people who check.

---

## 2. Wispr Flow in one page

**What it is.** A cloud dictation app founded 2021 by Tanay Kothari and Sahaj Garg (pivoted from a silent-speech neural wearable; Flow was the wearable's software layer). macOS Oct 2024 → Windows Mar 2025 → iOS Jun 2025 → Android Feb 2026. $81M confirmed raised (~$26M of it from the hardware era; $30M Series A led by Menlo, $25M extension at $700M post-money); a ~$260M Series B at ~$2B was reported May 2026 and remains unconfirmed closed.

**The product.** Hold-Fn push-to-talk (identical default gesture to warble), hands-free mode, a persistent bottom-of-screen "Flow Bar" pill showing a live waveform (not live transcription). Cloud ASR (Whisper-derived, per third parties) plus a fine-tuned Llama enhancement LLM on Baseten, with OpenAI/Anthropic/Cerebras post-processing. 104 languages with per-dictation auto-detect; ~60% of dictations are non-English. Filler removal, backtracking ("no, actually 4pm" keeps only the revision), auto-lists, tone matching per app, auto-learning dictionary (proper nouns from corrections, synced cross-device), snippets, Command Mode (paid, experimental voice editing), Scratchpad notes, an Insights dashboard with streaks and share cards. Onboarding is the industry benchmark: 16 steps, sequential permission cards, live mic test, sandboxed practice that guarantees the first dictation succeeds.

**The numbers.** Claimed p99 <700ms; third parties measure ~1.8s real-world. ~97% accuracy independently. Free tier: 2,000 words/week desktop, 1,000 on iPhone. Pro $15/mo or $144/yr. No lifetime option; teams currently run on Pro pricing (no separate Teams tier on the live pricing page); Enterprise custom. ~19-20% free-to-paid conversion. A gated Flow Voice Interface API exists (approval-only); broader developer API planned.

**The liabilities, by the verified record.** No offline mode at any price — architectural, not a toggle. Mandatory account. Privacy Mode is OFF by default, meaning dictation data may be used for training unless the user flips it; zero-retention requires configuring two separate toggles (default only for Enterprise/BAA). Late-2025: banned the anonymous Reddit user who documented undisclosed active-window image uploads (CTO apologized after it went viral; sequence rests on secondary accounts). April 2026 Wensen Wu forensics (v1.4.752): always-on system-wide CGEventTap (a stuck-modifier bug ate 145 spacebar presses in ~10 minutes), 1,688 app/URL events logged in 30 hours, full accessibility-tree scraping per dictation, a 694MB local SQLite hoard including 198MB of raw audio, hourly uploads even with usage-sharing off ("only uploading metadata"), and entitlements permitting dylib injection. Note: the investigation found the screenshot BLOB column NOT populated — the proven story is keystroke/URL/tree scope, not "screenshots every few seconds." Their original SOC 2 came via the discredited Delve pipeline; the A-LIGN re-audit yielded a clean Type I with Type II still in observation. "HIPAA compliant/ready" marketing, though HIPAA has no certification regime. Trustpilot 2.7/5 vs App Store 4.8/5 — recurring organic complaints: post-trial reliability, ~800MB idle RAM / 8% CPU (Electron), Login Items re-adding itself, AI cleanup that "rewrites what you said," a May 27–June 2, 2026 cluster of recurring latency/degradation incidents, and the word cap arriving exactly when the habit is formed.

---

## 3. Feature gap table

| Feature | Wispr Flow | warble | Verdict | Why |
|---|---|---|---|---|
| Read aloud / TTS | None, anywhere in product or docs | Kokoro-82M, select + ⌃V, follow-along panel | **warble-wins** | Category-of-one; their entire roadmap ignores it |
| Offline operation | Impossible — "transcription always occurs on the cloud" | 100% on-device, works with Wi-Fi off | **warble-wins** | Architectural; they can't copy it without rebuilding their accuracy story |
| Latency | <700ms claimed, ~1.8s observed | ~0.08s warm | **warble-wins** | 20x+ measured; demo-able side by side |
| Price / license | $144/yr, 2,000-word/wk free cap, closed source | Free, MIT | **warble-wins** | Their own cap converts habituated free users into warble prospects |
| Verifiable privacy | Policy-based; three documented trust breaches | Read the source, watch Little Snitch show nothing | **warble-wins** | Trust-by-construction vs trust-by-assertion |
| Idle footprint | ~800MB RAM / 8% CPU idle (Electron, community-benchmarked) | Native SwiftPM | **warble-wins** (once measured) | Publish honest numbers; users screenshot these |
| Push-to-talk core | Hold Fn, hands-free double-tap | Same | **parity** | Identical gesture; the fight is elsewhere |
| Learning dictionary | Auto-learn from corrections, starring, cross-device sync | Learns from corrections + spoken spelling, local | **parity** | warble matches the loved part; sync is irrelevant on one device |
| Usage dashboard | Insights: WPM, streaks, per-app, share cards (cloud) | Local dashboard: words, WPM, streaks, per-app, replay | **parity** → warble-wins on framing | "Your stats stay yours" — retention mechanics with zero telemetry |
| Cleanup levels / undo-AI-edit | None/Light/Medium/High + raw-transcript reveal | Deterministic cleanup + optional LLM polish | **gap-to-close** | Cheap; maps directly onto warble's existing pipeline stages, answers the "it rewrote me" complaint |
| Snippets (spoken trigger → expansion) | Yes | No | **gap-to-close** | Simple, fully local, no cloud needed |
| "Press enter" auto-send | Yes | No | **gap-to-close** | Trivial; huge for chat apps |
| Multi-shortcut + mouse binding | 4 shortcuts, mouse buttons | Fn-only | **gap-to-close** | Cheap ergonomics win for RSI users |
| Session recovery / long sessions | 20-min cap, Recover from history | Unverified | **gap-to-close** | Dictated words must be unlosable; ~/.warble recordings make Recover nearly free |
| Onboarding polish | The industry benchmark (16 steps, guaranteed first success) | Unknown / indie-grade | **gap-to-close** | "Polished compared to indie competitors" is aimed at apps like warble |
| Context awareness | Accessibility-text reading, sent to servers | None | **gap-to-close, local-only** | Ship "context that never leaves your Mac" — turn their scandal into a feature |
| Command Mode (voice editing) | Paid, experimental | No | **gap-to-ignore (for now)** | Nice-to-have; not a churn driver in the evidence; revisit after core gaps |
| 104 languages, auto-detect | Their hardest moat; 60% of dictations non-English | Parakeet English-centric, whisper.cpp fallback | **gap-to-ignore** | Concede the multilingual mass market; own "best English on-device" |
| Windows / iOS / Android | All four platforms | macOS only | **gap-to-ignore** | Solo dev; superwhisper/VoiceInk/Hex thrive Mac-first |
| Enterprise compliance (SOC 2, BAA, SSO) | Yes (with a checkered audit history) | No | **gap-to-ignore** | Not warble's buyer; "on-device" beats "HIPAA-ready cloud" for the actual regulated user |
| Notes / Scratchpad | Yes | No | **gap-to-ignore** | Scope creep; rotli exists, and it's not why anyone picks a voice layer |
| Gated API / integrations marketing | Approval-only API, 50+ named apps | Open source | **gap-to-ignore** | MIT + scriptable design is the better answer for the dev audience |

---

## 4. Where warble wins — the wedges, sharpened

**1. Verifiable privacy (not just "private").** Every dictation app promises privacy; only warble lets you check. Wispr's trust model is "believe our policy," and the record shows three moments where policy and binary diverged. The message is never "Wispr is spyware" — it's a comparison page whose Wispr column quotes only Wispr: "Transcription always occurs on the cloud." Privacy Mode off by default. Account required. US-only processing. Every cell linked to a primary source. Then three checkable proofs for warble: turn off Wi-Fi and dictate; run Little Snitch and watch nothing; read the repo. Sharpened message: **"Every dictation app promises privacy. One lets you verify it."**

**2. On-device / offline.** Not a privacy footnote — a capability. Works on planes, on dead Wi-Fi, in hospitals and law firms, and on days when the vendor's status page is red (Wispr logged a week-long cluster of latency and degradation incidents May 27–June 2, 2026). Sharpened message: **"Works on a plane. Works during their outage. Works forever."**

**3. Free + open source, no meter.** The community does the switcher math out loud: $15/mo → $8.49/mo → $25 one-time → $0. Wispr's own retention data (72% of characters by voice at month 6) guarantees free users smash the 2,000-word weekly cap right as the habit forms — that cap is warble's top-of-funnel. Sharpened message: **"No account. No meter. No trial cliff. MIT."** Put it where their pricing table would be.

**4. Bidirectional voice — the uncontested wedge.** Wispr and the entire free-local pack (Handy, VoiceInk, Hex, superwhisper) are dictation-only. warble reads back, with word-by-word follow-along. This is the only differentiator no one else in the category holds, so it leads, not trails. Sharpened message: **"It talks back — and it never talks to a server."** One line unifying the feature gap and the privacy gap.

**5. The dark instrument identity.** Wispr's rebrand fled to cream paper, Garamond, and lifestyle photography — deliberately vacating the credible-technology aesthetic. superwhisper holds local-first but with power-user roughness. The open lane is precise: local-first with Wispr-level polish, styled as instrument, not lifestyle — one electric-blue accent, mono type for the numbers, real waveforms as the illustration system, the gradient confined to the mark. Caution from the brand report: blue-on-dark is the #1 AI-startup cliché; warble escapes it by being terminal/hardware/signal, never marketing-gradient sprawl.

**6. Latency as a demo.** ~0.08s warm vs ~1.8s observed is the single most persuasive asset warble can produce: one side-by-side video, both apps, same sentence. Quantified claims are Wispr's own playbook ("4x faster than typing") — warble's numbers have the advantage of being locally verifiable.

---

## 5. What to steal

All of these are Wispr's genuinely good moves, re-implemented local-first.

1. **Sequential permission cards.** One permission per card, grant-one-reveal-next, each with a one-line "why," deep-linking via `x-apple.systempreferences:` URLs where macOS allows. Add a post-macOS-update re-verify check — silent Accessibility revocation is a documented support generator for them.
2. **Guaranteed first success.** Live mic-level meter before anything else, then one sandboxed practice dictation using a deliberately messy sentence ("Umm, let's meet Friday at 3 — no, actually 4") that shows the cleanup pipeline working. Then — Wispr can't do this part — demo read-aloud in the same sandbox: "select this paragraph, press ⌃V." Both halves of bidirectional voice land in minute one. Unlike Wispr: allow skip. Keep the spirit of "don't let them fail" via the mic check, not via a locked door.
3. **Get users into their own apps immediately.** Wispr's acknowledged retention unlock: users who only tested in the demo window churned. warble's first-run should end with a real dictation into Mail, Slack, or the user's terminal within ~60 seconds.
4. **The listening contract.** Distinct start ping + live waveform in the electric-blue accent + a visually distinct processing state. Hover the indicator → shows the hotkey. Unambiguous "it heard me."
5. **Cause-naming error copy + unlosable dictations.** Their escalating errors ("mic in use by another app," "mic disconnected") and History-Recover pattern. warble's local recordings under ~/.warble make Recover nearly free to build.
6. **Visible learning.** warble already learns from corrections — surface it ("warble learned: Parakeet"). Invisible learning earns no trust; Wispr's sparkle-flagged dictionary additions do.
7. **Stat reframing, locally.** WPM percentile vs typists, "corrections cleaned up for you" (quantifies the polish pipeline), words translated into human units, a glowing streak heatmap, optional locally-rendered share cards. Wispr's stickiest retention feature, with a story they structurally cannot tell: zero telemetry.
8. **Problem-first changelog voice.** Their best writing is the transparent incident postmortem ("Here's a transparent look at what went wrong"). This register is *more* native to open source — warble's release notes with commits as receipts.
9. **Poetic-functional naming.** Flow Bar, Scratchpad, Mouse Flow. Name warble's surfaces — the pill, the follow-along panel, the dictionary. Named things feel designed.
10. **Comparison-page SEO.** "Is Wispr Flow safe," "Wispr Flow offline," "Wispr Flow alternative" are proven queries currently farmed by thin competitor blogs. One scrupulously fair, primary-sourced /vs/wispr-flow page that concedes their strengths (accuracy, polish, real ZDR mode, clean A-LIGN Type I) will outrank the farm and earn HN trust precisely because it's fair.

---

## 6. What to ignore

1. **The multilingual arms race.** 104 languages with auto-detect is their hardest moat and 60% of their volume. Chasing it dilutes warble's "best English on-device" story; the whisper.cpp fallback is enough of an answer for now.
2. **Cross-platform expansion.** Windows/iOS/Android is a funded-team game. Mac-first is a respected position in this exact niche.
3. **Enterprise compliance machinery.** SOC 2, BAAs, SSO, admin dashboards — sales-motion features for a company with a sales team. warble's answer to the regulated buyer is architectural: the data never leaves.
4. **A persistent on-screen pill.** The Flow Bar is a recurring, quotable complaint ("a big annoying black rectangle") that even favorable reviewers disable in the first hour. warble's indicator should be transient by default — appear on keydown, vanish on completion — with an optional pinned mode. "No black rectangle squatting on your screen" is a legitimate line.
5. **Accounts, trials, caps, referral loops, waitlist gamification.** Their entire growth apparatus converts goodwill into a 2.7-star Trustpilot. warble's growth currency is stars, installs, and Show HN — friction-free by construction.
6. **Notification-driven engagement.** Six categories, all on by default, is part of why Flow feels needy. Teach via an in-dashboard checklist and occasional tips; if notifications exist at all, quiet defaults.
7. **Notes/Scratchpad scope creep.** A voice layer that also becomes a notes app is how a solo project loses focus (and Seth already has rotli).
8. **Overriding user intent, ever.** Login Items re-adding itself is Wispr's most resented behavior. warble never does anything the user turned off.

---

## 7. Roadmap priorities (ordered)

1. **Onboarding to Wispr's standard.** Sequential permission cards with deep links, live mic meter, sandboxed messy-dictation demo, read-aloud demo, skippable, ending in the user's own app within 60 seconds. *Evidence: "polished compared to indie competitors" is aimed at warble's class; the permissions gauntlet is where indie menu-bar apps die; Wispr's own churn fix was first-dictation-in-your-own-apps.*
2. **Never lose a dictation + long-session handling.** Recover-from-history for interrupted sessions; verify behavior on very long holds; cause-naming mic errors. *Evidence: Wispr treats dictated words as unlosable and users notice; their generic "Transcript failed to load" is a documented remaining weak spot warble can beat.*
3. **Cleanup levels + undo-polish.** None/Light/Medium/High mapped onto the existing deterministic-vs-LLM split, with a raw-transcript reveal. Default verbatim-leaning. *Evidence: "rewrites what you said instead of transcribing" is a sharp cross-camp complaint; warble's pipeline architecture makes "verbatim by default, polish on request" a one-setting answer.*
4. **The trust page + benchmark numbers.** A transparency doc (what warble hooks and why, what ~/.warble stores with export/clear and a size cap, what never happens), signed releases with checksums toward reproducible builds, plus published idle RAM/CPU and side-by-side latency video. *Evidence: the Wensen Wu piece is the template of the audit warble should invite; Wispr's 694MB silent hoard shows local storage is also a privacy surface; the 800MB/8% idle and ~1.8s numbers are the community's own ammunition.*
5. **Snippets + "press enter" auto-send + multi-shortcut/mouse bindings.** Three cheap parity closes in one release. *Evidence: the product-features report's explicit "gaps warble could close cheaply" list; auto-send is "huge for chat apps"; mouse triggers matter to the RSI audience warble should court.*
6. **Local-only context awareness.** Per-app tone/formatting via Accessibility APIs, processed on-device, never transmitted, off by default with a plain explanation. *Evidence: context awareness is the one loved Wispr feature warble lacks, and their scandal makes "context that never leaves your Mac" a positioning weapon, not just a feature.*
7. **Dashboard gamification pass.** Percentile framing, "corrections cleaned for you," human-unit word counts, glowing streak heatmap, locally-rendered share cards, visible dictionary learning. *Evidence: Insights is among Wispr's stickiest retention surfaces; warble already has the data locally and can add the mechanics with zero telemetry.*
8. **/vs/ comparison pages + Show HN.** /vs/wispr-flow (primary-sourced, fair), /vs/superwhisper, /vs/voiceink; then the launch: "the open-source Wispr Flow that also reads aloud." *Evidence: every competitor's growth moment was a Show HN; the "is Wispr Flow safe" query stream is proven; Wispr's own VoiceInk comparison page concedes open-source/one-time/offline as real advantages — the incumbent validates warble's axes.*

---

## 8. Positioning statement + taglines

**Positioning statement:**
warble is the voice layer for your Mac — speak to type, select to hear. It is the only voice tool that works in both directions, and the only one you can verify: 100% on-device, open source, free. No account, no cloud, no telemetry, no word meter. Nothing leaves your Mac — not your voice, not your screen, not your history. Turn off Wi-Fi and it still works. Read the source and it still holds.

**Taglines:**
1. It talks back — and it never talks to a server.
2. Nothing leaves your Mac. That's the whole architecture.
3. No account. No cloud. No meter. No asterisk.
4. Speak to type, select to hear. 100% on-device.
5. The dictation app that still works in airplane mode — and reads your answer back.

---

## 9. Risks

1. **Wispr ships read-aloud.** The bidirectional wedge is a feature gap, not an architectural one — a funded team could add cloud TTS in a quarter. Mitigation: make bidirectionality synonymous with warble now (it headlines everything), and note their version would still be cloud TTS: "it talks back through a server" is a weaker sentence.
2. **Wispr ships a local/hybrid model.** Their accuracy story and personalization stack depend on cloud, so full on-device is a rebuild — but a limited offline fallback would blunt "works on a plane." The verifiability wedge (open source, no account, no telemetry) survives; they cannot open-source or de-account without dismantling their business.
3. **Apple.** Materially better native dictation (or system-level on-device dictation + read-aloud in a macOS release) is the shared extinction event for this whole category. warble's hedges: system-wide any-app polish, the learning dictionary, the dashboard, and speed of iteration Apple won't match on a utility.
4. **The free-local pack erodes the wedge.** Handy (~26k stars, MIT, cross-platform, Whisper + Parakeet) already occupies "free + local + open source" with more distribution. If warble reads as "Handy but Mac-only," it loses the Show HN. Defense: bidirectional voice, the learning dictionary, the local dashboard, and design polish — the report evidence says indie local apps get dinged as "half-baked"; warble's bar is Wispr-grade craft.
5. **Wispr's trust rehabilitation succeeds.** A clean A-LIGN Type II, an EU region, genuinely opt-out-by-default training, and time could fade the incidents. warble's claims must therefore stand without the scandal: verifiability, offline, latency, price are true regardless of Wispr's conduct.
6. **Overclaiming.** The single self-inflicted risk. The banned reporter was anonymous (Ryan Shrott's cancellation posts are separate); the April 2026 forensics did *not* prove screenshot uploads (the BLOB column was unpopulated); training use requires the "unless Privacy Mode is on (off by default)" qualifier; their ZDR mode and clean Type I are real. warble's entire trust position is precision — one exaggerated claim about Wispr hands them the rebuttal and forfeits the moat.
7. **Solo-dev capacity.** Wispr ships monthly with 50 people; warble's roadmap above is realistically a year. The report evidence cuts both ways: reviewers in this niche weight developer responsiveness heavily (superwhisper is dinged for neglect), so a solo dev who ships and answers is itself a differentiator — but only while the shipping continues.
8. **English-centric models.** 60% of Wispr's dictations are non-English and India is their #2 market. warble concedes this deliberately, but every comparison table will list it; the honest answer ("best English dictation on-device; multilingual via Whisper fallback") must be stated, not hidden.

---

## Appendix A — gaps flagged by the completeness critic

*An adversarial completeness pass over the strategy above; treat these as the open work items of the analysis itself.*

**Missing dimensions**

1. **Accuracy is absent from the gap table.** Wispr gets ~97% independently; warble's Parakeet WER is never benchmarked. Transcript quality is the #1 switch-back driver, and the strategy has no plan to measure or publish it.
2. **The repo is private.** The entire wedge is "read the source," yet open-sourcing `SethMed7/warble` is never listed as a prerequisite or roadmap item. "MIT-licensed" is currently unverifiable by anyone.
3. **Local-model setup friction is ignored.** "Works immediately" uses Apple's engine; the 0.08s/Parakeet/Kokoro path requires "Set up better engines" with multi-hundred-MB downloads and Python subprocess servers (core/asr-server.py, llm-server.py). That download-and-wait step is the real local-app first-five-minutes killer vs Wispr's zero-setup cloud — the onboarding plan never addresses it.
4. **No success metrics, timeline, or MVP cut.** Risk 7 admits the roadmap is "a year" but nothing is sequenced toward a launch date or defines what winning looks like (stars, installs, retention).
5. **No sustainability story.** "Free forever from a solo dev" triggers abandonment fear in exactly this niche; no sponsorship/support/longevity answer.
6. **Competitive table is Wispr-only.** Risk 4 names Handy/VoiceInk/superwhisper as the real threat, yet there's no gap table against them — and Handy uses the same Parakeet, so warble's engine edge there is zero.

**Unverified/wrong claims**

7. **The latency comparison repeats Wispr's sin.** ~0.08s is warble's self-reported warm engine time, not end-to-end release-to-paste including cleanup/LLM polish; comparing it to Wispr's third-party 1.8s is asymmetric.
8. **"Read-aloud exists nowhere" is false as stated.** macOS ships Spoken Content (select + hotkey) free; Speechify/ElevenLabs Reader exist. The wedge is quality/follow-along, and "why not Apple's Speak Selection?" goes unanswered.
9. **Idle-footprint "warble-wins" is assumed.** Warm Parakeet + Kokoro + local LLM RAM may rival Wispr's 800MB; unmeasured.
10. **Apple risk is understated as hypothetical** — SpeechAnalyzer on-device APIs already shipped (macOS 26), available to every competitor.
11. **The strategist never audited warble itself**: table rows say "unverified"/"unknown" while the README documents Recent Dictations recovery, history replay, per-mode permissions. Sourcing for 80% retention, 40% MoM, 19-20% conversion, $8.49/$25 prices is absent.

**Missed opportunities**

12. A **Wispr import tool** (dictionary/history from their local SQLite hoard) as a concrete switch path; **Homebrew cask** and r/macapps/YouTube reviewer distribution; a deliberate **RSI/accessibility/Talon-community** motion; the EU/GDPR angle asserted but with no action attached.

---

## Appendix B — method

Produced 2026-07-11 by a multi-agent workflow: six specialist analysts (product features, onboarding/UX, pricing/GTM, brand/visual, privacy/architecture, community sentiment) researched the public record in parallel; each report's load-bearing claims were then independently adversarially fact-checked against primary sources before a strategist synthesized this document. Full dimension reports + fact-check verdicts: [wispr-flow-research.md](wispr-flow-research.md).
