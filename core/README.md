# warble core — the portable voice layer

The parts of warble that have **nothing to do with Apple**: the on-device engines and
text processing that any project can embed — a macOS app, a CLI, a Linux daemon, a
web/TS tool. Everything here runs **100% locally**; network access is limited to the
one-time model downloads you trigger explicitly, plus the warm servers' loopback-only
listeners (each binds `127.0.0.1` and never reaches out — see the contract below).

| File | Direction | What it does | Dependencies |
| --- | --- | --- | --- |
| `say.ts` | text → speech | Streams neural TTS with [Kokoro-82M](https://github.com/hexgrad/kokoro) (kokoro-js / ONNX). Emits audio chunks + the chunk text so a caller can follow along word-by-word. | `kokoro-js` (downloads an ~80 MB model once) |
| `say-server.ts` | text → speech (warm) | The same Kokoro pipeline kept resident in a tiny HTTP server, so each read skips the per-spawn model reload. Binds `127.0.0.1` only. | `kokoro-js`, bun |
| `asr-server.py` | speech → text (warm) | Warm Parakeet ASR server (sherpa-onnx kept loaded; ~0.05 s decodes). Binds `127.0.0.1` only. | `sherpa-onnx` |
| `llm-server.py` | text → polished text (warm) | Warm MLX cleanup server (the pinned Qwen model kept loaded). Binds `127.0.0.1` only; run with `HF_HUB_OFFLINE=1` it cannot fetch anything at request time. | `mlx-lm` |
| `clean.ts` | speech text → clean text | Deterministic transcript cleanup: drops fillers (`um`/`uh`), resolves self-corrections (`2 actually 3` → `3`), honors `scratch that`, collapses duplicate words. No LLM, no network. | none |
| `clean.test.ts` | — | Acceptance suite for `clean.ts` (`bun test`). | none |

## Why this is separate from the app

The OS integration — global hotkeys, the overlay panel, microphone capture, typing
into the focused app — is unavoidably per-platform and lives in `../apps/<platform>/`.
The **engine + text** layer here is not. Keeping it standalone means:

- the macOS app (`apps/macos`) is just one consumer of it;
- another project of yours can `import` the cleaner or the TTS helper directly;
- a future `apps/linux` or `apps/web` shell reuses this untouched.

## Embedding it

```sh
bun add ./core            # or copy say.ts / clean.ts into your project
```

```ts
import { clean } from "./core/clean.ts";
clean("um so the the report");   // -> "so the report"
```

`say.ts` is a stdin→stdout streaming helper (see the macOS `KokoroEngine` for the
wire format: one `<audio-path>\t<chunk text>` line per chunk). The transcription
engines warble uses (Parakeet via sherpa-onnx, whisper.cpp) are external on-device
binaries invoked as subprocesses — also cross-platform — and are installed by the
app's `setup` script, never bundled.

## The local-only contract

Stated precisely, because "no networking" would be false: this layer's only networking
is the three warm servers it ships — `asr-server.py`, `llm-server.py`, `say-server.ts` —
and each is a **loopback-only listener**: it binds `127.0.0.1` (read the bind call in
each file), serves warble's own process on the same machine, and initiates no outbound
connection (the LLM server additionally runs under `HF_HUB_OFFLINE=1`). Models are
fetched once, by an explicit setup step you run — never silently at runtime, never
per-use. Nothing you speak or read is ever sent anywhere; the full account is the app's
[transparency doc](../docs/transparency.md).
