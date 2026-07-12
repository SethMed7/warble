#!/bin/sh
# warble end-to-end latency bench (docs/benchmarks.md §1). Times the paste path a scripted run
# can reach — fixture WAV → transcribe → clean → dictionary → paste-ready string — via the
# in-process `--bench-e2e` flag of the DEBUG binary. Two modes:
#   warm — the daily path: engine already loaded; one process, N runs, run 1 discarded as warm-up
#   cold — the first dictation after launch: N fresh processes, the warm ASR server stopped
#          before each (warble re-warms it on your next real dictation)
# Excluded UI legs (key handling, recorder finalize, the paste event) are estimated in
# docs/benchmarks.md — never compare these numbers to a competitor's full round trip without
# adding those estimates back.
#
# usage: sh scripts/bench/latency.sh [--runs N] [--wav path] [--no-cold] [--no-warm]
#            [--engine parakeet-warm|parakeet|whisper|speechanalyzer|apple|stub]
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BIN="$ROOT/apps/macos/.build/debug/warble"
WAV="$ROOT/scripts/bench/fixtures/e2e-fixture.wav"
RUNS=10
DO_COLD=1
DO_WARM=1
ENGINE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --runs)    RUNS=$2; shift 2 ;;
    --wav)     WAV=$2; shift 2 ;;
    --engine)  ENGINE=$2; shift 2 ;;
    --no-cold) DO_COLD=0; shift ;;
    --no-warm) DO_WARM=0; shift ;;
    *) echo "usage: sh scripts/bench/latency.sh [--runs N] [--wav path] [--engine name] [--no-cold] [--no-warm]" >&2
       exit 2 ;;
  esac
done

[ -x "$BIN" ] || { echo "no debug binary — run: cd apps/macos && swift build" >&2; exit 2; }
[ -f "$WAV" ] || { echo "no wav: $WAV" >&2; exit 2; }

run_bench() { # $1 = run count; the forced engine (debug seam) keeps a number single-engine
  if [ -n "$ENGINE" ]; then env WARBLE_FORCE_ENGINE="$ENGINE" "$BIN" --bench-e2e "$WAV" "$1"
  else "$BIN" --bench-e2e "$WAV" "$1"; fi
}

# Only the auto chain / parakeet-warm involve the warm ASR server; never touch it otherwise.
USES_WARM_SERVER=0
{ [ -z "$ENGINE" ] || [ "$ENGINE" = "parakeet-warm" ]; } && USES_WARM_SERVER=1
ASR_PORT="${WARBLE_ASR_PORT:-8765}"
asr_healthy() { curl -s -m 1 "http://127.0.0.1:$ASR_PORT/health" >/dev/null 2>&1; }
kill_asr() { pkill -f asr-server.py 2>/dev/null; sleep 0.5; }
WAS_WARM=0
[ "$USES_WARM_SERVER" -eq 1 ] && asr_healthy && WAS_WARM=1

ENGINE_LABEL=${ENGINE:-"auto (the app's chain)"}
echo "warble e2e latency — wav=$(basename "$WAV") runs=$RUNS engine=$ENGINE_LABEL"
echo "measures: WAV -> transcribe -> clean -> dictionary -> paste-ready string"

FAIL=0
if [ "$DO_COLD" -eq 1 ]; then
  echo ""
  echo "--- cold (fresh process per run; warm ASR server stopped first) ---"
  MSFILE=$(mktemp "${TMPDIR:-/tmp}/warble-bench-cold.XXXXXX")
  n=1
  while [ "$n" -le "$RUNS" ]; do
    [ "$USES_WARM_SERVER" -eq 1 ] && kill_asr
    if OUT=$(run_bench 1); then
      MS=$(printf '%s\n' "$OUT" | sed -n 's/^run=1 ms=//p')
      echo "cold run $n: ${MS}ms"
      printf '%s\n' "$MS" >> "$MSFILE"
    else
      echo "cold run $n FAILED:"; printf '%s\n' "$OUT"; FAIL=1
    fi
    n=$((n + 1))
  done
  if [ -s "$MSFILE" ]; then
    printf 'cold summary: %s\n' "$(bun "$ROOT/scripts/bench/stats.ts" < "$MSFILE")"
  fi
  rm -f "$MSFILE"
fi

if [ "$DO_WARM" -eq 1 ]; then
  echo ""
  echo "--- warm (one process; run 1 below is a discarded warm-up) ---"
  if run_bench 1 >/dev/null 2>&1; then
    run_bench "$RUNS" || FAIL=1
  else
    echo "warm-up run FAILED — is an engine installed? (--engine stub always works)" >&2
    FAIL=1
  fi
fi

# Leave the warm server as we found it: off if it was off (warble re-warms on the next dictation).
[ "$USES_WARM_SERVER" -eq 1 ] && [ "$WAS_WARM" -eq 0 ] && kill_asr

exit "$FAIL"
