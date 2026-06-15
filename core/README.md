# voz core — the portable voice layer

The parts of voz that have **nothing to do with Apple**: the on-device engines and
text processing that any project can embed — a macOS app, a CLI, a Linux daemon, a
web/TS tool. Everything here runs **100% locally**; the only network access is the
one-time model download you trigger explicitly.

| File | Direction | What it does | Dependencies |
| --- | --- | --- | --- |
| `say.ts` | text → speech | Streams neural TTS with [Kokoro-82M](https://github.com/hexgrad/kokoro) (kokoro-js / ONNX). Emits audio chunks + the chunk text so a caller can follow along word-by-word. | `kokoro-js` (downloads an ~80 MB model once) |
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
engines voz uses (Parakeet via sherpa-onnx, whisper.cpp) are external on-device
binaries invoked as subprocesses — also cross-platform — and are installed by the
app's `setup` script, never bundled.

## The local-only contract

This layer contains **no networking code**. Models are fetched once, by an explicit
setup step you run — never silently at runtime, never per-use. Nothing you speak or
read is ever sent anywhere.
