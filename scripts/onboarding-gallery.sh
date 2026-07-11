#!/bin/sh
# warble card gallery — every onboarding card, Setup state, and pill state rendered to PNGs in
# one command, for human design review (DESIGN.md is the law the eyes check against):
#
#   sh scripts/onboarding-gallery.sh [out-dir]     default: /tmp/warble-onboarding-qa
#
# Everything renders offscreen at @2x through the DEBUG render seams (--render-onboarding,
# --render-setup, --render-pill) — no window, no permissions, no mic. QA output only; the
# gallery is never committed. The regression suite's `gallery` check runs this script and
# asserts every PNG lands, so the gallery can't silently rot.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$ROOT/apps/macos/.build/debug/warble"
OUT=${1:-/tmp/warble-onboarding-qa}

if [ ! -x "$BIN" ]; then
  echo "no debug binary — building first (swift build)…"
  ( cd "$ROOT/apps/macos" && swift build ) || exit 1
fi

mkdir -p "$OUT"
TOTAL=0
FAIL=0

render() { # render <flag> <state> <file>
  TOTAL=$((TOTAL + 1))
  if "$BIN" "$1" "$2" "$OUT/$3" >/dev/null 2>&1 && [ -s "$OUT/$3" ]; then
    printf '  %s\n' "$3"
  else
    FAIL=$((FAIL + 1))
    printf '  FAILED: %s (%s %s)\n' "$3" "$1" "$2"
  fi
}

# The tour: every step the machine declares (a new card joins the gallery automatically), plus
# every preview-state variant the render seam knows (keep this case in sync with
# OnboardingCLI.render's variants table — the regression check counts on it).
echo "onboarding cards:"
STEPS=$("$BIN" --onboarding-state 2>/dev/null | awk '{print $2}')
if [ -z "$STEPS" ]; then
  echo "  FAILED: --onboarding-state printed nothing"
  exit 1
fi
i=0
for id in $STEPS; do
  i=$((i + 1))
  render --render-onboarding "$id" "onboarding-$i-$id.png"
  case "$id" in
    mic | ax) VARIANTS="granted" ;;
    meter)    VARIANTS="nomic" ;;
    practice) VARIANTS="done nomic" ;;
    read)     VARIANTS="done noax" ;;
    *)        VARIANTS="" ;;
  esac
  for v in $VARIANTS; do
    render --render-onboarding "$id+$v" "onboarding-$i-$id+$v.png"
  done
done

echo "setup states:"
for s in fresh installing installed failed; do
  render --render-setup "$s" "setup-$s.png"
done

echo "pill states:"
for s in listening listening+hint listening+cap processing processing+hint landed copied error; do
  render --render-pill "$s" "pill-$s.png"
done

printf 'gallery: %d/%d renders → %s\n' "$((TOTAL - FAIL))" "$TOTAL" "$OUT"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
