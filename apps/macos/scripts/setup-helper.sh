#!/bin/sh
# Installs warble's canonical cleanup helper (pure Bun TypeScript, fully on-device)
# to ~/.warble. Without it, warble uses the built-in Swift cleaner. Requires bun
# (https://bun.sh).
# Run in-place by the app's "Set up better engines…"; not meant to be run standalone.
set -e
DIR="$HOME/.warble"
LEGACY="$HOME/.dictado"
RAW="https://raw.githubusercontent.com/SethMed7/warble/main/core"
command -v bun >/dev/null 2>&1 || { echo "bun not found — install from https://bun.sh first"; exit 1; }
mkdir -p "$DIR"

HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -n "$HERE" ] && [ -f "$HERE/../../../core/clean.ts" ]; then
  cp "$HERE/../../../core/clean.ts" "$DIR/"
else
  curl -fsSL "$RAW/clean.ts" -o "$DIR/clean.ts"
fi

# Carry a learned dictionary forward from the legacy ~/.dictado (non-destructive copy).
if [ -f "$LEGACY/dictionary.json" ] && [ ! -f "$DIR/dictionary.json" ]; then
  cp "$LEGACY/dictionary.json" "$DIR/dictionary.json"
  echo "Migrated your dictionary from ~/.dictado → ~/.warble/dictionary.json."
fi
echo
echo "Cleanup helper installed to ~/.warble (no dependencies, nothing to download)."

# --- Optional: the Parakeet engine (best accuracy, non-OpenAI, no silence noise) ---
# warble works out of the box on Apple's on-device recognizer. Installing NVIDIA
# Parakeet (CC-BY-4.0) via the sherpa-onnx binary upgrades accuracy and removes any
# length cap — fully on-device, nothing from OpenAI. ~25MB binary + ~482MB model.
# Lives in the shared ~/.cache/sherpa; skipped silently when piped (no TTY) or if you decline.
SHERPA_DIR="$HOME/.cache/sherpa"
SHERPA_VER="v1.13.2"
have_parakeet() { ls "$SHERPA_DIR"/*/bin/sherpa-onnx-offline >/dev/null 2>&1 && ls "$SHERPA_DIR"/*parakeet*/encoder.int8.onnx >/dev/null 2>&1; }
# Resumable fetch: -C - continues an interrupted download instead of restarting it. A leftover
# that is already complete makes the range unsatisfiable (curl exit 22/33 on HTTP 416) — treat
# that as done; tar validates the archive right after.
fetch() {
  curl -fL -C - "$1" -o "$2" && return 0
  rc=$?
  if [ "$rc" -eq 22 ] || [ "$rc" -eq 33 ]; then [ -s "$2" ] && return 0; fi
  return "$rc"
}
if ! have_parakeet; then
  printf 'Install the Parakeet engine (NVIDIA, best accuracy, non-OpenAI)? [y/N] '
  read -r ans 2>/dev/null || ans=""
  case "$ans" in
    [Yy]*)
      mkdir -p "$SHERPA_DIR"
      case "$(uname -m)" in arm64) ARCH="osx-arm64" ;; *) ARCH="osx-x64" ;; esac
      REL="https://github.com/k2-fsa/sherpa-onnx/releases/download"
      if ! ls "$SHERPA_DIR"/*/bin/sherpa-onnx-offline >/dev/null 2>&1; then
        echo "Downloading sherpa-onnx $SHERPA_VER ($ARCH, ~25MB)…"
        fetch "$REL/$SHERPA_VER/sherpa-onnx-$SHERPA_VER-$ARCH-shared.tar.bz2" "$SHERPA_DIR/sherpa-bin.tar.bz2" \
          && tar xjf "$SHERPA_DIR/sherpa-bin.tar.bz2" -C "$SHERPA_DIR" && rm -f "$SHERPA_DIR/sherpa-bin.tar.bz2"
      fi
      if ! ls "$SHERPA_DIR"/*parakeet*/encoder.int8.onnx >/dev/null 2>&1; then
        echo "Downloading Parakeet TDT 0.6B model (~482MB)…"
        fetch "$REL/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2" "$SHERPA_DIR/parakeet.tar.bz2" \
          && tar xjf "$SHERPA_DIR/parakeet.tar.bz2" -C "$SHERPA_DIR" && rm -f "$SHERPA_DIR/parakeet.tar.bz2"
      fi
      have_parakeet && echo "Parakeet installed → warble will use it automatically." \
        || echo "Install incomplete — warble falls back to Apple's on-device recognizer."
      ;;
    *) echo "Skipped Parakeet — warble uses Apple's on-device recognizer until you add it." ;;
  esac
fi
