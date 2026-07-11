#!/bin/sh
# warble WER bench (docs/benchmarks.md §2). Scores every installed engine on a corpus of
# clip.wav + clip.txt (reference transcript) pairs, pooled WER via wer.ts. With no corpus dir
# given it synthesizes one: the ten public-domain Harvard sentences (fixtures/harvard.txt)
# rendered by macOS `say` at two voices × two rates. Synthetic TTS audio UNDERESTIMATES
# real-world WER (clean signal, no room noise, no disfluency) — the honest long-term number
# needs a recorded corpus, which drops into the same wav+txt layout:
#
#   usage: sh scripts/bench/wer-corpus.sh [corpus-dir]
#
# Engines are forced one at a time via the DEBUG-build WARBLE_FORCE_ENGINE seam (no fallback —
# a number is always one engine's own). Missing/unauthorized engines are skipped with a note,
# never faked: the Apple engine typically can't authorize Speech from an unbundled CLI binary.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BIN="$ROOT/apps/macos/.build/debug/warble"
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/warble-bench-wer.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
CORPUS="${1:-}"

[ -x "$BIN" ] || { echo "no debug binary — run: cd apps/macos && swift build" >&2; exit 2; }

if [ -z "$CORPUS" ]; then
  CORPUS="$SCRATCH/corpus"
  mkdir -p "$CORPUS"
  # Two installed voices from a preferred list (say silently substitutes the default voice for
  # a missing one, which would skew comparability — probe first).
  VOICES=""
  COUNT=0
  for v in Samantha Alex Daniel Karen Fred; do
    if say -v '?' 2>/dev/null | grep -q "^$v "; then
      VOICES="$VOICES $v"; COUNT=$((COUNT + 1))
      [ "$COUNT" -ge 2 ] && break
    fi
  done
  [ -n "$VOICES" ] || { echo "no usable say voices found" >&2; exit 2; }
  echo "synthesizing corpus: 10 Harvard sentences ×$VOICES × rates 175/220 wpm"
  i=0
  while IFS= read -r line; do
    i=$((i + 1))
    for v in $VOICES; do
      for r in 175 220; do
        f=$(printf '%s/h%02d-%s-%s' "$CORPUS" "$i" "$v" "$r")
        say -v "$v" -r "$r" -o "$f.wav" --data-format=LEI16@16000 "$line"
        printf '%s\n' "$line" > "$f.txt"
      done
    done
  done < "$ROOT/scripts/bench/fixtures/harvard.txt"
fi

FIRST=$(ls "$CORPUS"/*.wav 2>/dev/null | sed -n 1p)
[ -n "$FIRST" ] || { echo "no .wav clips in $CORPUS" >&2; exit 2; }

echo "corpus: $(ls "$CORPUS"/*.wav | wc -l | tr -d ' ') clips in $CORPUS"
for e in parakeet-warm parakeet whisper apple; do
  # Probe availability on one clip; skipping honestly beats a silently substituted engine.
  if ! env WARBLE_FORCE_ENGINE="$e" "$BIN" --transcribe "$FIRST" >/dev/null 2>&1; then
    echo "engine=$e not available (skipped)"
    continue
  fi
  TSV="$SCRATCH/$e.tsv"
  : > "$TSV"
  for wav in "$CORPUS"/*.wav; do
    txt="${wav%.wav}.txt"
    [ -f "$txt" ] || continue
    hyp=$(env WARBLE_FORCE_ENGINE="$e" "$BIN" --transcribe "$wav" 2>/dev/null) || hyp=""
    hyp=$(printf '%s' "$hyp" | tr '\n\t' '  ') # keep the TSV one line per clip
    printf '%s\t%s\n' "$(cat "$txt")" "$hyp" >> "$TSV"
  done
  echo "engine=$e $(bun "$ROOT/scripts/bench/wer.ts" --pairs "$TSV" | sed -n 's/^pooled //p')"
done
echo "note: parakeet-warm and parakeet share one model — accuracy is identical, only latency differs"
