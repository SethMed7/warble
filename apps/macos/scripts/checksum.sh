#!/bin/sh
# Computes the SHA-256 of a release artifact and records it in a checksums.txt next to it —
# the download-integrity half of release integrity (ROADMAP 0.7). Sparkle's EdDSA signature
# (sign_update, see update-appcast.sh) already covers the in-app auto-update path; this covers
# the OTHER path — someone who grabbed the .dmg straight off the GitHub release page and wants to
# confirm the bytes weren't altered in transit or on GitHub's end, independent of Sparkle.
#
#   sh scripts/checksum.sh <path-to-dmg> [checksums-file]   # default checksums-file: <dmg's dir>/checksums.txt
#
# Idempotent: re-running for the same filename replaces its line rather than duplicating it, so
# release.sh can call this every cut without checksums.txt growing stale duplicate entries.
# Format is plain `shasum -a 256` output (one "<hex>  <filename>" line per artifact), so anyone can
# verify with the standard tool, no warble-specific script required:
#   shasum -a 256 -c checksums.txt
set -e
FILE="$1"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "usage: sh scripts/checksum.sh <file> [checksums-file]" >&2
  exit 1
fi
OUT="${2:-$(dirname "$FILE")/checksums.txt}"
NAME=$(basename "$FILE")
LINE="$(shasum -a 256 "$FILE" | awk '{print $1}')  $NAME"

TMP="$OUT.tmp.$$"
if [ -f "$OUT" ]; then
  # Drop any existing line for this exact filename, keep every other entry (other versions'
  # dmgs stay recorded — checksums.txt is a running ledger, not a single-release scratchpad).
  grep -v "  $NAME\$" "$OUT" > "$TMP" 2>/dev/null || : > "$TMP"
else
  : > "$TMP"
fi
printf '%s\n' "$LINE" >> "$TMP"
sort -o "$TMP" "$TMP"
mv "$TMP" "$OUT"
echo "✓ $LINE"
echo "  → $OUT"
