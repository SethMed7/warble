#!/bin/sh
# warble bootstrap — set up the OPTIONAL on-device engines, with full transparency and your consent.
#
# warble already works the moment you launch it: dictation falls back to Apple's on-device recognizer,
# read-aloud to the macOS system voice, cleanup to a built-in pass. NOTHING here is required. This
# script only offers the premium on-device upgrades — and it installs NOTHING without you typing "y",
# telling you exactly what each step does, where it comes from, and how big it is first.
#
# Everything stays on your Mac. The only network use is downloading the open models you approve.

set -e

# warble was "voz" through 0.1.8 — adopt an existing ~/.voz home before touching anything.
[ -d "$HOME/.voz" ] && [ ! -d "$HOME/.warble" ] && mv "$HOME/.voz" "$HOME/.warble" || true
cd "$(dirname "$0")"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
dim()  { printf '\033[2m%s\033[0m\n' "$1"; }
has()  { command -v "$1" >/dev/null 2>&1; }
ask()  { printf '\033[1m%s\033[0m [y/N] ' "$1"; read -r a </dev/tty; [ "$a" = y ] || [ "$a" = Y ]; }

clear 2>/dev/null || true
bold "warble · set up better engines"
echo "Local, on-device upgrades. Nothing installs without your yes. Ctrl-C any time."
echo

# ── Capability check ──────────────────────────────────────────────────────────
ARCH=$(uname -m)
MACOS=$(sw_vers -productVersion)
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
DISK_FREE_GB=$(df -g / | awk 'NR==2{print $4}')
APPLE_SILICON=no; [ "$ARCH" = arm64 ] && APPLE_SILICON=yes

bold "Your Mac"
echo "  chip:        $ARCH ($( [ "$APPLE_SILICON" = yes ] && echo 'Apple Silicon' || echo 'Intel' ))"
echo "  macOS:       $MACOS"
echo "  memory:      ${RAM_GB} GB"
echo "  free disk:   ${DISK_FREE_GB} GB"
echo
if [ "$DISK_FREE_GB" -lt 3 ]; then
  echo "⚠️  Under 3 GB free — the models below may not fit. Free up space first if you want them."
  echo
fi

# ── Transparency: macOS permissions warble will ask for, and why ──────────────────
# Shown BEFORE anything installs. warble requests each one only when you first use the
# feature that needs it — never up front, and never anything it doesn't use.
bold "Permissions warble asks macOS for (only when first used)"
echo "  • Microphone — to hear you while you HOLD the dictation hotkey. Audio is transcribed"
echo "    on-device and never saved."
echo "  • Accessibility — to paste the finished text into whatever app you're typing in, and"
echo "    (optional) to notice spelling fixes you make so it can learn your words."
echo "  • Speech Recognition — only for Apple's built-in on-device recognizer fallback; the"
echo "    audio and recognition stay on your Mac."
echo "  Grant/revoke any of these any time in System Settings → Privacy & Security."
echo

# ── Transparency: what can be installed, and exactly where ─────────────────────
bold "What this can install, and where"
echo "  Everything below is OPTIONAL, downloaded only after you type 'y', and lives in your"
echo "  home folder — never inside the app, nothing system-wide, no admin/sudo:"
echo "    ~/.bun                  bun JS runtime (~40 MB)            — runs the cleanup + helpers"
echo "    ~/.warble/                 helper scripts, your dictionary + history, the warm servers"
echo "    ~/.warble/kokoro           Kokoro neural read-aloud voices (~90 MB)"
echo "    ~/.warble/asr-venv         Python venv for the warm Parakeet dictation server"
echo "    ~/.warble/llm-venv         Python venv (mlx-lm) for the warm LLM cleanup server"
echo "    ~/.cache/sherpa         Parakeet engine + model (~600 MB)"
echo "    ~/.cache/huggingface    the MLX cleanup model (Qwen2.5-1.5B, ~0.9 GB)"
echo "  Every engine runs locally and binds 127.0.0.1 only — no cloud, no API keys, no telemetry."
echo "  To remove later: delete the model caches in ~/.cache, and ~/.warble (note: your dictionary"
echo "  and dictation history live in ~/.warble too)."
echo

# ── bun (shared JS runtime for cleanup + Kokoro/Parakeet helpers) ──────────────
if has bun || [ -x "$HOME/.bun/bin/bun" ]; then
  dim "✓ bun already installed."
else
  echo "bun is a small, fast JS runtime (~40 MB) warble uses to run the cleanup + helper scripts."
  echo "Source: https://bun.sh/install"
  if ask "Install bun?"; then curl -fsSL https://bun.sh/install | bash; else dim "Skipped bun (cleanup will use the built-in Swift pass)."; fi
fi
echo

# ── Kokoro neural voices (nicer read-aloud) ────────────────────────────────────
echo "$(bold 'Kokoro neural voices') — warm, natural read-aloud (~90 MB model, Apache-2.0)."
echo "Without it, read-aloud uses the built-in macOS voice."
if ask "Install Kokoro voices?"; then sh setup-kokoro.sh; fi
echo

if [ -f setup-kokoro-server.sh ]; then
  echo "$(bold 'Kokoro warm server') — keeps the voice model resident so each read starts instantly."
  if ask "Set up the warm read-aloud server?"; then sh setup-kokoro-server.sh; fi
  echo
fi

# ── Parakeet ASR (top dictation accuracy) ──────────────────────────────────────
echo "$(bold 'Parakeet dictation engine') (NVIDIA, via sherpa-onnx) — best accuracy, ~600 MB."
echo "Without it, dictation uses Apple's on-device recognizer (already good)."
if [ "$APPLE_SILICON" = yes ] && [ "$RAM_GB" -ge 8 ]; then
  if ask "Install Parakeet + the warm ASR server?"; then sh setup-helper.sh && [ -f setup-asr.sh ] && sh setup-asr.sh; fi
else
  echo "↳ Skipping Parakeet: it wants Apple Silicon + 8 GB RAM (you have $ARCH / ${RAM_GB} GB)."
fi
echo

# ── On-device LLM polish ───────────────────────────────────────────────────────
echo "$(bold 'LLM polish') — punctuation + filler removal via a small on-device model."
echo "warble installs its own model (Qwen2.5-1.5B via MLX, ~0.9 GB, Apache-2.0) — no Ollama needed."
if [ "$RAM_GB" -lt 8 ]; then
  echo "↳ Skipping LLM polish: recommends 8 GB+ RAM."
elif [ "$APPLE_SILICON" = yes ]; then
  if ask "Set up LLM polish?"; then sh setup-cleaner.sh; fi
else
  echo "↳ Intel Mac: MLX needs Apple Silicon, so warble uses a self-contained llama.cpp model instead."
  if ask "Set up LLM polish?"; then sh setup-cleaner.sh; fi
fi
echo

bold "Done."
echo "Open warble's menu to pick engines. Anything you skipped, re-run this any time:"
echo "  menu → Set up better engines…   (or:  sh \"$PWD/bootstrap.sh\")"
