# warble `/vs/` pages — status: **drafts**

*ROADMAP 0.7: "`/vs/` comparison pages, drafted." This directory is that item — five pages, written
ahead of the public launch, sitting in a private repo with no site to publish them onto yet.*

## What this is

Five comparison pages, one per real alternative, plus this index. They are markdown files with no
site plumbing and no navigation — nothing here is live. They exist so the writing gets done, and
the fact-checking gets done, **before** the audience arrives (the whole point of ROADMAP 0.7: "the
trust dossier"). When warble goes public (ROADMAP 1.0, gate item 4: "the transparency doc +
comparison pages are live and every claim primary-sourced"), these become `/vs/wispr-flow`,
`/vs/superwhisper`, `/vs/voiceink`, `/vs/handy`, and `/vs/apple-built-ins` on whatever the real site
is at the time.

**A timing note, stated plainly:** these pages describe warble as it will be at that launch — open
repo, public releases, "read the source" a claim anyone can actually check. Today the repo is
still private (deliberately — see [ROADMAP.md](../../ROADMAP.md): "the repo stays private while the
product is polished to the public bar"). That's not a hole in these pages; it's why they're drafts
and not published.

**A currency note, also stated plainly:** competitor pricing, versions, and feature lists move.
Every fact below is dated and sourced to the competitor's own site, repo, or documentation at the
time of writing (2026-07). Before any page actually goes live, re-verify every sourced fact —
prices change, features ship, licenses get relicensed. Stale competitor facts are exactly the kind
of "grep-falsifiable overclaim" product.md §4.9 warns against, just aimed the other direction.

## The form every page follows

1. **What they do better** — leads with the honest concession. If a page can't say something real
   here, it isn't ready.
2. **The honest comparison table** — only rows warble can actually source and stand behind:
   license, price, offline, accounts, telemetry, read-aloud, learning dictionary, latency, WER.
   Latency/WER are warble's own measured numbers from [docs/benchmarks.md](../benchmarks.md),
   **with the method caveat stated immediately next to them** — never a bare number implying a
   fair fight with a competitor's differently-measured claim (product.md §4.9).
3. **Who should pick them** — a real answer, not a strawman.
4. **Who should pick warble** — same standard.
5. **Sources** — every competitor fact links to where it came from: their own site, repo, docs, or
   (for Wispr Flow specifically) the verified teardown at
   [docs/competitive/wispr-flow.md](../competitive/wispr-flow.md).

## The pages

| Page | Who they are | The one thing this page can't skip |
| --- | --- | --- |
| [wispr-flow.md](wispr-flow.md) | The category leader — funded, cloud-only, the onboarding benchmark | Precision on their incident record: quote only what the fact-checked record supports ([docs/competitive/wispr-flow.md](../competitive/wispr-flow.md) §Risks item 6 is binding here) |
| [superwhisper.md](superwhisper.md) | The paid local-first rival — Whisper/Parakeet on-device, optional cloud modes, $8.49–$249.99 | Its local-vs-cloud split is real and needs to be stated precisely, not flattened to "not local" |
| [voiceink.md](voiceink.md) | GPL-3.0, one-time-purchase, whisper.cpp + Parakeet, macOS-only | Same nuance: local transcription by default, optional cloud transcription/enhancement via BYOK |
| [handy.md](handy.md) | MIT, free, cross-platform, ~26k GitHub stars, the same Parakeet engine warble ships | The engine parity has to be faced head-on — warble's answer is the layer above the engine, not the engine itself |
| [apple-built-ins.md](apple-built-ins.md) | Dictation + Spoken Content, built into every Mac, free, no install | The one page where the competitor genuinely already does both verbs — the honest comparison is depth, not existence |

## What proves these stay honest

`sh scripts/regression.sh --only vs` is the structural half: every page still leads with a real
concession, still carries the sourcing rows, still cites [docs/benchmarks.md](../benchmarks.md) for
warble's own numbers with the caveat stated, and none of the known-overclaim or competitor-incident
overreach phrases have crept back in. It cannot verify a competitor's price is still current — that
recheck is a human step, immediately before these pages actually ship.
