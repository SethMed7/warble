# warble vs. VoiceInk

*DRAFT — staged for warble's public launch, not yet linked from anywhere. See
[docs/vs/README.md](README.md) for what "draft" means here. Every VoiceInk fact below is cited to
its GitHub repository, LICENSE file, or its own site (2026-07); GitHub's repository metadata was
read directly, not via a third-party review.*

VoiceInk is the source-available rival most often pitched as "the open-source Wispr Flow" — and
it's a fair pitch: GPL-3.0, local Whisper/Parakeet transcription, a one-time price instead of a
subscription, and an active developer (5,502 GitHub stars, latest release v1.79 as of 2026-07-12).

## What they do better

- **Actually shipping, actively.** v1.79 landed May 2026; the project is a working product with
  paying customers today, not a roadmap.
- **A built-in AI Assistant mode** — a conversational, ChatGPT-like voice assistant inside the
  dictation flow. warble has nothing like it and isn't building it (product.md's non-goals rule
  out a chat/assistant surface; a voice layer isn't a chatbot).
- **Context-aware "Smart Modes"** that auto-detect the frontmost app/URL and switch writing profiles
  accordingly, with up to 10 custom modes — a more elaborate per-app system than warble's cleanup
  categories, shipped and in users' hands today rather than a recent addition.
- **A real source-available option at $0.** "As an open-source project, you can build VoiceInk
  yourself... though you will not get automatic updates or priority support" — genuinely free if
  you're willing to build from source; a licensed build ($25 one Mac / $39 two / $49 three,
  one-time, no subscription) supports the developer and adds updates.
- **A homebrew cask** (`brew install --cask voiceink`) — a distribution channel warble doesn't have
  yet (ROADMAP 1.0 lists this as a launch item).

## The honest comparison table

| | VoiceInk | warble |
| --- | --- | --- |
| License | GPL-3.0 (source available; "not accepting pull requests" per its README — you can fork, not contribute upstream) | MIT (open source at public launch; contributions welcome, see CONTRIBUTING.md) |
| Price | $25/$39/$49 one-time (1/2/3 Macs); free to build from source without updates/priority support | Free, no tier, nothing to unlock |
| Offline | Local Whisper/Parakeet by default and genuinely offline; **optional cloud transcription and cloud AI-enhancement are supported via user-supplied API keys** (OpenAI/Anthropic/Gemini/Groq/Cerebras/OpenRouter), or Ollama on localhost to keep enhancement local too | Always on-device — no cloud code path exists in Dictate or Speak at all, at any setting |
| Accounts | None required per their own privacy policy: "VoiceInk does not collect or transmit any personal data by default" | None |
| Telemetry | No telemetry/analytics/crash-reporting disclosed in their privacy policy | None, ever |
| Read aloud | None found in the repository or docs — dictation and an AI voice-assistant reply, no general-purpose text-to-speech | Kokoro-82M neural voices, select + ⌃V, word-by-word follow-along panel |
| Learning dictionary | Yes — a "Personal Dictionary" for custom words/terms/replacements | Yes — learns from corrections and spoken spelling, local-only |
| Latency (warm) | No published benchmark found | ~65 ms median engine time (warm Parakeet), + an estimated ~20–60 ms for legs the harness can't reach — see the note below |
| WER | Self-reported "99% accuracy" (their own marketing copy, not independently measured or method-disclosed) | 0.9% WER (Parakeet) on a 40-clip synthetic corpus — see the note below |

**A note on the two warble rows, and on VoiceInk's accuracy claim:** warble's latency figure is its
own paste-path harness timing over a fixture clip plus an *estimated* allowance for legs the harness
can't reach — not a full release-to-text-visible measurement. Its WER figure is scored on
**studio-clean synthetic speech**, a corpus that structurally underestimates real-world error for
every engine — warble's included. VoiceInk's "99% accuracy" is their own stated marketing figure
with no published method or corpus, so it isn't placed in the same column as an independently
verified number — it's presented here exactly as they present it, self-reported. Full method and
reproduction commands: [docs/benchmarks.md](../benchmarks.md).

### The local/cloud split, stated precisely

VoiceInk's core transcription is local by default and the app is genuinely usable fully offline —
but its own privacy policy documents an optional cloud transcription path ("If you choose to use
cloud transcription... your audio file is sent to your selected provider") and an optional cloud
AI-enhancement path (transcript text only, never audio, sent to a chosen LLM provider unless you
point it at a local Ollama instance). That's a real, disclosed, opt-in design — and a structurally
different one from warble, where no such cloud path exists to opt into in the first place.

## Who should pick them

If you want a built-in voice assistant alongside dictation, per-app Smart Modes with more
granularity than warble currently ships, a one-time purchase you can spread across up to three
Macs, or you're comfortable building from source under GPL-3.0 for a truly $0 install — VoiceInk is
a strong, real choice, and one of the better-maintained apps in this category.

## Who should pick warble

If you want a license that welcomes outside contributions (MIT, not "fork only"), a product with no
cloud option to configure at all rather than one you have to remember to leave off, or — again —
the verb VoiceInk doesn't offer: reading text back to you in the same voice, following along word by
word, closing the loop on what you just dictated — warble is built for you.

## Sources

- [github.com/beingpax/VoiceInk](https://github.com/beingpax/VoiceInk) — README, features,
  contribution policy, star count and release history (read via the GitHub API, 2026-07-12)
- [github.com/beingpax/VoiceInk/blob/main/LICENSE](https://github.com/beingpax/VoiceInk/blob/main/LICENSE) —
  the GPL-3.0 license text
- [tryvoiceink.com](https://tryvoiceink.com/) — pricing tiers, platform requirement (macOS 14.4+)
- [tryvoiceink.com/privacy](https://tryvoiceink.com/privacy) — account/telemetry statements and the
  local-vs-cloud transcription/enhancement mechanics, quoted above
- [docs/benchmarks.md](../benchmarks.md) — warble's own latency/WER numbers, method, and caveats
