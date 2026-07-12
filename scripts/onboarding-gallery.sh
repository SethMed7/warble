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
for s in listening listening+hint listening+cap processing processing+hint landed landed+sent landed+readback copied error; do
  render --render-pill "$s" "pill-$s.png"
done

echo "history detail (context awareness's inspect half):"
# --render-history has no state argument of its own — the scenario lives in the seeded WARBLE_HOME
# (like every other WARBLE_HOME-sandboxed check), so it can't use the generic render() helper above.
GAL_TMP="$(mktemp -d "${TMPDIR:-/tmp}/warble-gallery.XXXXXX")"
trap 'rm -rf "$GAL_TMP"' EXIT
HIST_GAL_HOME="$GAL_TMP/history"
mkdir -p "$HIST_GAL_HOME/legacy" "$HIST_GAL_HOME/context"
cp "$ROOT/scripts/fixtures/history-legacy.jsonl" "$HIST_GAL_HOME/legacy/history.json"
printf '%s\n' '{"id":"ctx-modern","ts":1799800000,"day":"2026-07-11","text":"following up on the q3 numbers now","words":7,"durationMs":2900,"appBundleId":"com.apple.mail","appName":"Mail","engine":"parakeet","kind":"dictate","context":{"app":"Mail","category":"mail","words":42,"preview":"Re: the Q3 numbers are in and they look good for the…"}}' \
  > "$HIST_GAL_HOME/context/history.json"
for s in legacy context; do
  TOTAL=$((TOTAL + 1))
  if env WARBLE_HOME="$HIST_GAL_HOME/$s" "$BIN" --render-history "$OUT/history-$s.png" >/dev/null 2>&1 \
    && [ -s "$OUT/history-$s.png" ]; then
    printf '  history-%s.png\n' "$s"
  else
    FAIL=$((FAIL + 1))
    printf '  FAILED: history-%s.png\n' "$s"
  fi
done

echo "dashboard retention pass (Home + the share card, empty and populated):"
# Same idiom: the scenario lives in the seeded WARBLE_HOME, not a state argument. Dates are
# relative to "now" so the populated scenario shows a real streak/heatmap no matter when this runs.
RET_GAL_HOME="$GAL_TMP/retention"
mkdir -p "$RET_GAL_HOME/empty" "$RET_GAL_HOME/populated"
RET_GAL_TS=$(date +%s)
{
  printf '{"id":"ret1","ts":%s,"day":"%s","text":"ship the myela engine today","words":5,"durationMs":1800,"appBundleId":"com.tinyspeck.slackmacgap","appName":"Slack","engine":"parakeet","kind":"dictate","correctionsCleaned":1}\n' \
    "$((RET_GAL_TS - 90000))" "$(date -v-1d +%Y-%m-%d)"
  printf '{"id":"ret2","ts":%s,"day":"%s","text":"final report is ready for review","words":6,"durationMs":2000,"appBundleId":"com.apple.mail","appName":"Mail","engine":"parakeet","kind":"dictate","correctionsCleaned":0}\n' \
    "$RET_GAL_TS" "$(date +%Y-%m-%d)"
} > "$RET_GAL_HOME/populated/history.json"
printf '{"id":"retl1","ts":%s,"word":"Myela","from":"miele"}\n' "$RET_GAL_TS" > "$RET_GAL_HOME/populated/learned.json"
for s in empty populated; do
  render_home() { env WARBLE_HOME="$RET_GAL_HOME/$s" "$BIN" --render-home "$OUT/home-$s.png"; }
  TOTAL=$((TOTAL + 1))
  if render_home >/dev/null 2>&1 && [ -s "$OUT/home-$s.png" ]; then
    printf '  home-%s.png\n' "$s"
  else
    FAIL=$((FAIL + 1))
    printf '  FAILED: home-%s.png\n' "$s"
  fi
done
TOTAL=$((TOTAL + 1))
if env WARBLE_HOME="$RET_GAL_HOME/populated" "$BIN" --render-share-card "$OUT/share-card.png" >/dev/null 2>&1 \
  && [ -s "$OUT/share-card.png" ]; then
  printf '  share-card.png\n'
else
  FAIL=$((FAIL + 1))
  printf '  FAILED: share-card.png\n'
fi

printf 'gallery: %d/%d renders → %s\n' "$((TOTAL - FAIL))" "$TOTAL" "$OUT"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
