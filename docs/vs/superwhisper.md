# warble vs. superwhisper

*DRAFT — staged for warble's public launch, not yet linked from anywhere. See
[docs/vs/README.md](README.md) for what "draft" means here. Every superwhisper fact below is cited
to superwhisper's own site or docs (2026-07); nothing here is sourced to a third-party review.*

superwhisper is the paid local-first rival, and the app most often recommended alongside warble in
the "privacy-conscious dictation" conversation. It genuinely runs local models — the r/macapps
consensus already treats it as the on-device answer to Wispr Flow, and it earned that.

## What they do better

- **Cross-platform today.** macOS, Windows, and iOS, right now. warble is Mac-only (a deliberate
  choice — see product.md §6 — but a real gap if you need Windows or iPhone).
- **A genuinely flexible engine picker.** Local Whisper (Tiny through Large V3 Turbo) and Parakeet
  V2/V3, plus — if you choose to enable it — cloud models (GPT-5, Claude Haiku 4.5, Llama 4 and
  others) with bring-your-own-key access. That range is real breadth warble doesn't offer.
- **A real vocabulary/replacement system with an auto-trainer.** Custom vocabulary hints feed the
  transcription model directly, deterministic post-transcription replacements apply on top, and a
  companion "Trainer" tool can mine your own recording history for terms you say often — a more
  automated version of what warble's dictionary does by hand.
- **A stated no-telemetry policy in their own privacy page**, and they say it plainly: "We do not
  collect any usage data when you use Superwhisper. We respect your right to privacy and do not
  track or log your usage of Superwhisper in any way." That's a real commitment, publicly written
  down.
- **A one-time lifetime option** ($249.99) for people who'd rather never think about a subscription
  again — a real alternative to warble's free-forever model for anyone who wants to directly fund
  the app.

## The honest comparison table

| | superwhisper | warble |
| --- | --- | --- |
| License | Closed source, proprietary — no public repository found | MIT (open source at public launch) |
| Price | Free tier (unlimited small local models); Pro $8.49/mo, $84.99/yr, or $249.99 lifetime | Free, no tier, nothing to unlock |
| Offline | Local Whisper/Parakeet models run fully offline on Apple Silicon ("Superwhisper works offline, so you can transcribe anytime"); **cloud models are opt-in** and require internet + a chosen provider — the free tier's "unlimited small local models" claim is genuinely offline, the Pro cloud-model option is not | Yes, always — no cloud code path exists in the app at all |
| Accounts | Not required to state per their own docs for the free tier; license activation for Pro implies an account/purchase record | None |
| Telemetry | Their own privacy policy: "We do not collect any usage data... do not track or log your usage... in any way"; some third-party reviews note licensing-verification or crash-report traffic distinct from that claim, which this page can't independently confirm either way | None, ever |
| Read aloud | None found in their product pages or docs — speech-to-text only | Kokoro-82M neural voices, select + ⌃V, word-by-word follow-along panel |
| Learning dictionary | Yes — a vocabulary + replacements system, plus an auto-trainer that mines your recording history for terms | Yes — learns from corrections and spoken spelling, local-only |
| Latency (warm) | No published benchmark found | ~65 ms median engine time (warm Parakeet), + an estimated ~20–60 ms for legs the harness can't reach — see the note below |
| WER | No published benchmark found | 0.9% WER (Parakeet) on a 40-clip synthetic corpus — see the note below |

**A note on the two warble rows:** the latency figure is warble's own paste-path harness timing
(WAV → transcription → cleanup → paste-ready string) over a fixture clip, plus an *estimated*
allowance for legs the harness can't reach (key-up handling, WAV finalize, the paste event) — not a
full release-to-text-visible measurement. The WER figure is scored on **studio-clean synthetic
speech** (macOS `say`, two voices × two rates), a corpus that structurally underestimates
real-world error for every engine tested — warble's included. superwhisper hasn't published a
comparable number on any corpus, so there's nothing to compare against here; these numbers describe
warble alone. Full method and reproduction commands: [docs/benchmarks.md](../benchmarks.md).

### The local/cloud split, stated precisely

superwhisper's marketing leads with offline capability, and the free tier's local-model path
genuinely is offline. But the product is *architected* for a cloud option — Pro unlocks cloud LLM
formatting and larger cloud models, chosen per-mode in setup — which is a meaningfully different
architecture from warble's, where there is no cloud code path to opt into at all, ever, at any
price. Neither framing is a gotcha; it's the actual shape of the two products.

## Who should pick them

If you need Windows or iPhone dictation today, want the widest range of pluggable engines including
frontier cloud models when you choose to use them, or would rather pay once ($249.99) and be done
than run something free forever from a solo developer — superwhisper is a strong, honest choice.

## Who should pick warble

If you want a product with **no cloud code path at all** (not "off by default" — architecturally
absent), you're Mac-only and want that to be someone's whole focus rather than one of three
platforms, or you want the one verb superwhisper doesn't offer — reading text back to you, in the
same voice, following along word by word — warble is built for you.

## Sources

- [superwhisper.com](https://superwhisper.com/) — platforms, pricing, offline claim
- [superwhisper.com/privacy](https://superwhisper.com/privacy) — telemetry and data-retention
  statements, quoted above
- [superwhisper.com/docs/get-started/introduction](https://superwhisper.com/docs/get-started/introduction) —
  cloud/local model selection, license/account mechanics
- [superwhisper.com/docs/get-started/interface-vocabulary](https://superwhisper.com/docs/get-started/interface-vocabulary) —
  the vocabulary/replacements/trainer system
- [docs/benchmarks.md](../benchmarks.md) — warble's own latency/WER numbers, method, and caveats
