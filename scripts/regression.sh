#!/bin/sh
# warble regression — the single deterministic gate. New features extend THIS file with a named
# check; the full story (coverage map, env seams, what stays manual) is docs/testing.md.
#
#   sh scripts/regression.sh                 run everything (engine-free by default)
#   sh scripts/regression.sh --list          name every check
#   sh scripts/regression.sh --only <name>   run one check (repeat or comma-separate for more)
#   WARBLE_REGRESSION_FULL=1 sh scripts/regression.sh   also exercise the warm-engine extras
#
# Engine-free by default: every default check passes on a machine with NO premium engines
# installed — deterministic seams (WARBLE_FAULT, WARBLE_FORCE_ENGINE=stub, WARBLE_DISABLE_LLM,
# WARBLE_MAX_HOLD_SECS) and sandboxes (WARBLE_HOME, WARBLE_DICTIONARY) keep every check hermetic;
# nothing touches the real ~/.warble or your dictionary. Exits 0 only when every check passed.
# `--only` assumes an existing debug binary (run `--only build` first when in doubt).
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$ROOT/apps/macos/.build/debug/warble"
PASS=0
FAIL=0

# Every check, in run order. Names are the --only/--list vocabulary; each maps to check_<name>
# (dashes become underscores). "warm" runs only under WARBLE_REGRESSION_FULL=1 (or an explicit
# --only warm).
ALL_CHECKS="core build unit version cleanup cleanup-level dictionary selftest engine errors hold-cap recovery retranscribe recover-raw bench warm"

describe() {
  case "$1" in
    core)          echo "core/ acceptance suite (bun install + bun test)" ;;
    build)         echo "swift build (debug) — the binary every CLI check runs" ;;
    unit)          echo "swift test — Dictate pure-logic unit tests (cleaner twin, spell-out, cap math, hallucination filter)" ;;
    version)       echo "--version matches Info.plist" ;;
    cleanup)       echo "cleanup levels: --clean + all four --cleanup levels, engine-free" ;;
    cleanup-level) echo "cleanup level persists across processes; old polish pref migrates" ;;
    dictionary)    echo "--apply/--pronounce over a fixture dictionary + learn-threshold promotion" ;;
    selftest)      echo "--selftest: learn-from-edits detection + history-event codability" ;;
    engine)        echo "--engine names a known engine tier" ;;
    errors)        echo "cause-naming taxonomy verbatim + engine-missing / transcribe-fail faults" ;;
    hold-cap)      echo "session cap story resolves; compressed clock warns then stops cleanly" ;;
    recovery)      echo "orphaned in-flight clip -> FAILED history event, audio kept, idempotent" ;;
    retranscribe)  echo "FAILED event resolves in place on --retranscribe (stub engine)" ;;
    recover-raw)   echo "happy-path recovery persists the raw transcript (undo-polish in the store)" ;;
    bench)         echo "benchmark harness smoke: wer/stats tests, latency over the stub engine, footprint" ;;
    warm)          echo "warm-engine extras: premium --engine + a real --speak (WARBLE_REGRESSION_FULL=1)" ;;
  esac
}

# --- helpers ---------------------------------------------------------------------------------

section() { printf '\n=== %s ===\n' "$1"; }
ok()      { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
bad()     { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

# step <name> <command string> — streams output, judged by exit code. Runs in a
# subshell so a cd inside the command never leaks.
step() {
  step_name=$1
  if ( eval "$2" ); then ok "$step_name"; else bad "$step_name"; fi
}

# expect <name> <expected stdout> <command...> — exact match on stdout, exit 0 required.
expect() {
  exp_name=$1
  exp_want=$2
  shift 2
  exp_got=$("$@" 2>/dev/null)
  exp_status=$?
  if [ "$exp_status" -eq 0 ] && [ "$exp_got" = "$exp_want" ]; then
    ok "$exp_name"
  else
    bad "$exp_name (exit $exp_status; got \"$exp_got\", want \"$exp_want\")"
  fi
}

require_bin() {
  [ -x "$BIN" ] && return 0
  bad "debug binary missing at apps/macos/.build/debug/warble — run: sh scripts/regression.sh --only build"
  return 1
}

# All fixtures live here; the trap removes everything at once.
REGTMP=$(mktemp -d "${TMPDIR:-/tmp}/warble-regression.XXXXXX")
trap 'rm -rf "$REGTMP"' EXIT

# The fixture dictionary makes --apply/--pronounce/bench deterministic on any machine (the env
# var outranks the real dictionary; see Lexicon.fileURL / Pronouncer.fileURL).
DICT="$REGTMP/dict.json"
printf '%s\n' '{"corrections":{"miele":"Myela"},"pronunciations":{"myela":"my-ell-uh"}}' > "$DICT"

# make_orphan <home> — plant the exact wreckage a crash leaves in a sandbox store: an in-flight
# WAV (16 kHz mono 16-bit PCM, 32000 bytes = 1.0s of audio) whose RIFF/data sizes are still ZERO,
# since AVAudioFile finalizes the header only on close. Backdated: files fresher than a few
# seconds are skipped as possibly-live recordings.
make_orphan() {
  mkdir -p "$1/inflight"
  {
    printf 'RIFF\0\0\0\0WAVEfmt '
    printf '\020\0\0\0\001\0\001\0\200\076\0\0\0\175\0\0\002\0\020\0'
    printf 'data\0\0\0\0'
    dd if=/dev/zero bs=8000 count=4 2>/dev/null
  } > "$1/inflight/inflight-regression.wav"
  touch -t "$(date -v-5M +%Y%m%d%H%M.%S)" "$1/inflight/inflight-regression.wav"
}

# Pin the store gates (Save recordings / Keep history) to their defaults (on) for a check, and
# restore whatever the machine had after. The unbundled debug binary uses the "warble" defaults
# domain — NOT the installed app's io.github.sethmed7.voz — so real preferences are never touched.
pin_store_defaults() {
  PIN_SAVE_AUDIO=$(defaults read warble insightsSaveAudio 2>/dev/null || true)
  PIN_HISTORY=$(defaults read warble insightsHistory 2>/dev/null || true)
  defaults delete warble insightsSaveAudio >/dev/null 2>&1
  defaults delete warble insightsHistory >/dev/null 2>&1
}
restore_store_defaults() {
  [ -n "$PIN_SAVE_AUDIO" ] && defaults write warble insightsSaveAudio -int "$PIN_SAVE_AUDIO" >/dev/null 2>&1
  [ -n "$PIN_HISTORY" ] && defaults write warble insightsHistory -int "$PIN_HISTORY" >/dev/null 2>&1
}

# Pin the persisted cleanup level for a check; restore after.
pin_cleanup_level() {
  PIN_LEVEL=$("$BIN" --cleanup-level 2>/dev/null)
  "$BIN" --cleanup-level "$1" >/dev/null 2>&1
}
restore_cleanup_level() { "$BIN" --cleanup-level "$PIN_LEVEL" >/dev/null 2>&1; }

# --- checks ----------------------------------------------------------------------------------

# The core acceptance-tested cleaner (deterministic, no engines).
check_core() {
  if ( cd "$ROOT/core" && bun install --silent ); then
    ok "core: bun install"
    step "core: bun test" "cd \"$ROOT/core\" && bun test"
  else
    bad "core: bun install"
    bad "core: bun test (skipped: install failed)"
  fi
}

# The debug build the CLI checks run against.
check_build() {
  step "swift build (debug)" "cd \"$ROOT/apps/macos\" && swift build"
  [ -x "$BIN" ] || bad "debug binary present at apps/macos/.build/debug/warble"
}

# Pure-logic unit tests (apps/macos/Tests/DictateTests): the BasicCleaner twin runs the SAME
# acceptance cases as core/clean.test.ts so the Swift/TS cleaners can't drift, plus SpellOut,
# HoldCap math, and the hallucination filter. Engine-free; shares swift build's artifacts.
# Judged on swift test's own exit code (never a pipeline's), and the XCTest summary line must
# exist — so an emptied test target can't pass silently.
check_unit() {
  UNIT_OUT=$(cd "$ROOT/apps/macos" && swift test 2>&1)
  UNIT_STATUS=$?
  UNIT_SUMMARY=$(printf '%s\n' "$UNIT_OUT" | grep "Executed .* tests" | tail -n 1 | sed 's/^[[:space:]]*//')
  if [ "$UNIT_STATUS" -eq 0 ] && [ -n "$UNIT_SUMMARY" ]; then
    ok "swift test (Dictate pure-logic units) — $UNIT_SUMMARY"
  else
    bad "swift test (Dictate pure-logic units) (exit $UNIT_STATUS)"
    printf '%s\n' "$UNIT_OUT" | tail -n 30
  fi
}

check_version() {
  require_bin || return
  VERSION=$(plutil -extract CFBundleShortVersionString raw "$ROOT/apps/macos/Info.plist" 2>/dev/null)
  if [ -n "$VERSION" ]; then
    expect "--version matches Info.plist ($VERSION)" "warble $VERSION" "$BIN" --version
  else
    bad "read CFBundleShortVersionString from apps/macos/Info.plist"
  fi
}

# Cleanup levels (ROADMAP 0.3). None must be verbatim; light must equal the deterministic --clean
# result; medium/high must degrade to the deterministic result with no LLM (WARBLE_DISABLE_LLM=1
# hides an installed one so this check is identical on every machine).
check_cleanup() {
  require_bin || return
  expect "--clean drops fillers and duplicates" "so the report" \
    "$BIN" --clean "um so the the report"
  expect "--cleanup none returns input verbatim" "um so the the report" \
    "$BIN" --cleanup none "um so the the report"
  CLEAN_OUT=$("$BIN" --clean "um so the the report" 2>/dev/null)
  expect "--cleanup light equals --clean" "$CLEAN_OUT" \
    "$BIN" --cleanup light "um so the the report"
  expect "--cleanup medium falls back deterministically (engine-free)" "so the report" \
    env WARBLE_DISABLE_LLM=1 "$BIN" --cleanup medium "um so the the report"
  expect "--cleanup high falls back deterministically (engine-free)" "so the report" \
    env WARBLE_DISABLE_LLM=1 "$BIN" --cleanup high "um so the the report"
}

# The cleanup-level setting must round-trip through UserDefaults across processes, and the old
# "Polish with AI" preference must migrate (on -> medium). Uses the "warble" defaults domain (the
# unbundled debug binary), so real preferences are never touched; the prior level is restored.
check_cleanup_level() {
  require_bin || return
  ORIG_LEVEL=$("$BIN" --cleanup-level 2>/dev/null)
  defaults delete warble cleanupLevel >/dev/null 2>&1
  defaults write warble llmCleanupEnabled -bool true
  expect "old polish-on preference migrates to medium" "medium" "$BIN" --cleanup-level
  defaults delete warble llmCleanupEnabled >/dev/null 2>&1
  expect "cleanup level defaults to light" "light" "$BIN" --cleanup-level
  expect "--cleanup-level set prints the new level" "high" "$BIN" --cleanup-level high
  expect "cleanup level round-trips through UserDefaults" "high" "$BIN" --cleanup-level
  "$BIN" --cleanup-level "$ORIG_LEVEL" >/dev/null 2>&1  # restore whatever was set before
}

# The dictionary applied both directions, plus the learn-from-corrections frequency gate — all
# against throwaway fixture files, never the real dictionary.
check_dictionary() {
  require_bin || return
  expect "--apply uses the dictionary" "ship the Myela engine" \
    env WARBLE_DICTIONARY="$DICT" "$BIN" --apply "ship the miele engine"
  expect "--pronounce uses the dictionary" "read my-ell-uh aloud" \
    env WARBLE_DICTIONARY="$DICT" "$BIN" --pronounce "read Myela aloud"
  LEARN_DICT="$REGTMP/learn-dict.json"
  rm -f "$LEARN_DICT"
  LEARN_OUT=$(env WARBLE_DICTIONARY="$LEARN_DICT" "$BIN" --learn-test deval Dhaval 2>/dev/null)
  if printf '%s\n' "$LEARN_OUT" | grep -q "PROMOTED → rule 'deval' → 'Dhaval'" \
    && printf '%s\n' "$LEARN_OUT" | grep -q "dictionary now maps 'deval' → Dhaval"; then
    ok "repeated corrections promote at the learn threshold"
  else
    bad "repeated corrections promote at the learn threshold (got \"$LEARN_OUT\")"
  fi
}

check_selftest() {
  require_bin || return
  SELFTEST=$("$BIN" --selftest 2>&1)
  if [ $? -eq 0 ] && printf '%s\n' "$SELFTEST" | grep -q "ALL PASS"; then
    ok "--selftest (ALL PASS)"
  else
    bad "--selftest"
    printf '%s\n' "$SELFTEST"
  fi
}

# Engine-free assertion: --engine must name a real tier ("Apple Speech" is the zero-install floor).
check_engine() {
  require_bin || return
  ENGINE=$("$BIN" --engine 2>/dev/null)
  case "$ENGINE" in
    "Parakeet (warm)" | "Parakeet" | "whisper.cpp" | "Apple Speech")
      ok "--engine names a known engine ($ENGINE)" ;;
    *)
      bad "--engine names a known engine (got \"$ENGINE\")" ;;
  esac
}

# Cause-naming errors (ROADMAP 0.3). --errors prints the whole taxonomy as "domain/reason: copy";
# asserting it verbatim makes any copy change deliberate. The WARBLE_FAULT seam (compiled into
# DEBUG builds only — this script always runs the debug binary) then forces the two failure paths
# provable headlessly: the engine-missing floor and a failed transcription. The mic faults need a
# live recording session — the by-hand procedure is in docs/testing.md.
check_errors() {
  require_bin || return
  ERRORS_WANT="dictate/mic-permission: grant Microphone access in System Settings
dictate/mic-busy: mic is in use by another app
dictate/mic-disconnected: mic disconnected mid-dictation
dictate/no-mic: no microphone found
dictate/record-failed: couldn't start recording
dictate/engine-warming: engine still warming up — try again in a moment
dictate/processing-timeout: took too long — press Fn to retry
dictate/transcribe-failed: transcription failed
dictate/transcribe-failed-kept: transcription failed — recording kept
dictate/engine-missing: premium engine not installed — using Apple engine
dictate/hold-cap: hit the 20-minute cap
speak/render-failed: voice engine failed
speak/read-cut-off: read cut off
speak/voice-missing: premium voice not installed — using Apple voice
speak/no-selection: no text selected"
  expect "--errors prints the full cause-naming taxonomy" "$ERRORS_WANT" "$BIN" --errors

  expect "engine-missing fault forces the Apple floor" "Apple Speech" \
    env WARBLE_FAULT=engine-missing "$BIN" --engine

  EM_NOTE=$(env WARBLE_FAULT=engine-missing "$BIN" --engine 2>&1 >/dev/null)
  if [ "$EM_NOTE" = "premium engine not installed — using Apple engine" ]; then
    ok "engine-missing names its cause on stderr"
  else
    bad "engine-missing names its cause on stderr (got \"$EM_NOTE\")"
  fi

  TF_MSG=$(env WARBLE_FAULT=transcribe-fail "$BIN" --transcribe /dev/null 2>&1 >/dev/null)
  TF_STATUS=$?
  if [ "$TF_STATUS" -ne 0 ] && [ "$TF_MSG" = "transcription failed" ]; then
    ok "transcribe-fail fault names its cause and exits non-zero"
  else
    bad "transcribe-fail fault names its cause (exit $TF_STATUS; got \"$TF_MSG\")"
  fi
}

# Long-session hardening (ROADMAP 0.3). The 20-minute cap and its warn-then-stop story resolve
# through HoldCap; --hold-cap prints the resolved numbers + the named stop cause exactly, and
# WARBLE_MAX_HOLD_SECS (a debug-build seam) compresses the cap so the machine runs in seconds.
# --hold-cap-sim then drives the REAL session clock (HoldCapClock) at a 4s cap: the countdown must
# tick before the cap fires (the binary exits non-zero if it didn't) and the run must end capped.
# Timing jitter only shifts the countdown values, so the assertion is structural (some warn tick +
# a final "capped"), not exact. What remains manual (docs/testing.md): the pill's countdown
# visuals over a real 20-minute hold.
check_hold_cap() {
  require_bin || return
  expect "--hold-cap resolves the default 20-minute cap" \
    "cap 1200s · warn at 1140s · on stop: hit the 20-minute cap" "$BIN" --hold-cap
  expect "WARBLE_MAX_HOLD_SECS compresses the cap (debug seam)" \
    "cap 6s · warn at 3s · on stop: hit the 6-second cap" \
    env WARBLE_MAX_HOLD_SECS=6 "$BIN" --hold-cap
  SIM_OUT=$(env WARBLE_MAX_HOLD_SECS=4 "$BIN" --hold-cap-sim 2>&1)
  SIM_STATUS=$?
  SIM_LAST=$(printf '%s\n' "$SIM_OUT" | tail -n 1)
  if [ "$SIM_STATUS" -eq 0 ] && printf '%s\n' "$SIM_OUT" | grep -q "^warn " && [ "$SIM_LAST" = "capped" ]; then
    ok "hold-cap clock warns then stops cleanly (4s compressed run)"
  else
    bad "hold-cap clock warns then stops cleanly (exit $SIM_STATUS; got \"$SIM_OUT\")"
  fi
}

# Dictation recovery (ROADMAP 0.3 — "never lose a word"). Simulate an interrupted dictation
# headlessly in a sandbox store (WARBLE_HOME — the real ~/.warble is never touched): the scan must
# repair the orphan's stale WAV header (or the clip reads as empty: 0.0s), and with
# WARBLE_FAULT=transcribe-fail forcing every engine to fail, the clip must land as a FAILED
# history event with the audio intact — engine-free and deterministic.
check_recovery() {
  require_bin || return
  RHOME="$REGTMP/recovery-home"
  rm -rf "$RHOME"
  make_orphan "$RHOME"
  pin_store_defaults
  RECOVER_OUT=$(env WARBLE_HOME="$RHOME" WARBLE_FAULT=transcribe-fail "$BIN" --recover-scan 2>/dev/null)
  if printf '%s\n' "$RECOVER_OUT" | grep -q "recovered as failed event — audio kept (1.0s)"; then
    ok "interrupted dictation recovers as a FAILED history event (header repaired: 1.0s)"
  else
    bad "interrupted dictation recovers as a FAILED history event (got \"$RECOVER_OUT\")"
  fi
  if grep -q '"status":"failed"' "$RHOME/history.json" 2>/dev/null; then
    ok "FAILED event persisted in history.json"
  else
    bad "FAILED event persisted in history.json"
  fi
  KEPT_AUDIO=$(printf '%s\n' "$RECOVER_OUT" | sed -n 's/^audio: //p')
  if [ -n "$KEPT_AUDIO" ] && [ -s "$KEPT_AUDIO" ]; then
    ok "recovered audio kept intact in the audio store"
  else
    bad "recovered audio kept intact in the audio store (path \"$KEPT_AUDIO\")"
  fi
  if [ ! -e "$RHOME/inflight/inflight-regression.wav" ]; then
    ok "in-flight clip consumed after recovery"
  else
    bad "in-flight clip consumed after recovery"
  fi
  expect "recovery scan is idempotent (no orphan left)" "no in-flight dictation found" \
    env WARBLE_HOME="$RHOME" "$BIN" --recover-scan
  restore_store_defaults
}

# Re-transcribe (ROADMAP 0.3 recovery, part two): a FAILED history event must resolve IN PLACE
# when the pipeline is run again over its kept recording — the History button's exact path,
# headless via --retranscribe. The failure is staged as in check_recovery; the re-run uses the
# stub engine (WARBLE_FORCE_ENGINE=stub, a DEBUG fixed-utterance transcriber — no model, no Speech
# auth), cleanup pinned to light so the resolved text and raw transcript are exact.
check_retranscribe() {
  require_bin || return
  RHOME="$REGTMP/retranscribe-home"
  rm -rf "$RHOME"
  make_orphan "$RHOME"
  pin_store_defaults
  pin_cleanup_level light
  env WARBLE_HOME="$RHOME" WARBLE_FAULT=transcribe-fail "$BIN" --recover-scan >/dev/null 2>&1
  if grep -q '"status":"failed"' "$RHOME/history.json" 2>/dev/null; then
    ok "staged: FAILED event with kept audio"
  else
    bad "staged: FAILED event with kept audio (recover-scan didn't land one)"
  fi
  expect "--retranscribe resolves the FAILED event in place" \
    "re-transcribed (5 words) — resolved in place" \
    env WARBLE_HOME="$RHOME" WARBLE_FORCE_ENGINE=stub WARBLE_DISABLE_LLM=1 "$BIN" --retranscribe
  if grep -q '"text":"so the quick brown fox"' "$RHOME/history.json" 2>/dev/null \
    && ! grep -q '"status":"failed"' "$RHOME/history.json" 2>/dev/null; then
    ok "resolved event carries the transcript and no failed status"
  else
    bad "resolved event carries the transcript and no failed status (history: $(cat "$RHOME/history.json" 2>/dev/null))"
  fi
  if grep -q '"raw":"um so the the quick brown fox"' "$RHOME/history.json" 2>/dev/null; then
    ok "raw transcript persisted on resolve (undo-polish)"
  else
    bad "raw transcript persisted on resolve (undo-polish)"
  fi
  expect "--retranscribe is idempotent (nothing failed left)" "no failed dictation found" \
    env WARBLE_HOME="$RHOME" "$BIN" --retranscribe
  restore_cleanup_level
  restore_store_defaults
}

# Undo-polish raw persistence (ROADMAP 0.3) through the REAL store: a successful recovery runs the
# normal record() path, and because cleanup (pinned to light) changed the stub's messy utterance,
# history.json must keep BOTH the cleaned text and the verbatim raw transcript.
check_recover_raw() {
  require_bin || return
  RHOME="$REGTMP/recover-raw-home"
  rm -rf "$RHOME"
  make_orphan "$RHOME"
  pin_store_defaults
  pin_cleanup_level light
  expect "happy-path recovery transcribes into History (stub engine)" \
    "recovered (5 words) — it's in History" \
    env WARBLE_HOME="$RHOME" WARBLE_FORCE_ENGINE=stub WARBLE_DISABLE_LLM=1 "$BIN" --recover-scan
  if grep -q '"text":"so the quick brown fox"' "$RHOME/history.json" 2>/dev/null \
    && grep -q '"raw":"um so the the quick brown fox"' "$RHOME/history.json" 2>/dev/null; then
    ok "cleaned text AND raw transcript persisted in history.json"
  else
    bad "cleaned text AND raw transcript persisted (history: $(cat "$RHOME/history.json" 2>/dev/null))"
  fi
  restore_cleanup_level
  restore_store_defaults
}

# Benchmark harness smoke (ROADMAP 0.3 "honest numbers, measured"). The real numbers live in
# docs/benchmarks.md and are gathered by hand against real engines; this smoke proves the harness
# itself on ANY machine: the WER/stats math (bun test + an exact CLI check), the latency harness
# end-to-end over the committed fixture WAV through the stub engine, and the footprint sampler's
# ps parsing via its self row.
check_bench() {
  require_bin || return
  step "bench: bun test (wer + stats)" "cd \"$ROOT/scripts/bench\" && bun test ."
  expect "bench: wer.ts scores one substitution in four words exactly" \
    "wer=0.250 errors=1 (S=1 D=0 I=0) N=4" \
    bun "$ROOT/scripts/bench/wer.ts" --ref "the quick brown fox" --hyp "the quick brown box"
  # Latency harness on the stub engine: cleanup pinned to light and the fixture dictionary in
  # force, so the paste-ready text is exact. --no-cold keeps regression away from the cold mode,
  # which manages the user's warm ASR server.
  pin_cleanup_level light
  BENCH_OUT=$(env WARBLE_DICTIONARY="$DICT" WARBLE_DISABLE_LLM=1 \
    sh "$ROOT/scripts/bench/latency.sh" --runs 2 --engine stub --no-cold 2>&1)
  BENCH_STATUS=$?
  restore_cleanup_level
  if [ "$BENCH_STATUS" -eq 0 ] \
    && printf '%s\n' "$BENCH_OUT" | grep -q "^runs=2 ok=2 .*median_ms=" \
    && printf '%s\n' "$BENCH_OUT" | grep -q "^text=so the quick brown fox$"; then
    ok "latency harness runs the fixture through the stub pipeline (2 runs, sane summary)"
  else
    bad "latency harness runs the fixture through the stub pipeline (exit $BENCH_STATUS; got \"$BENCH_OUT\")"
  fi
  FOOT_OUT=$(bun "$ROOT/scripts/bench/footprint.ts" --smoke 2>&1)
  if [ $? -eq 0 ] && printf '%s\n' "$FOOT_OUT" | grep -q "^footprint: 2 samples" \
    && printf '%s\n' "$FOOT_OUT" | grep -q "^total (running)"; then
    ok "footprint sampler parses ps and reports a total (smoke)"
  else
    bad "footprint sampler smoke (got \"$FOOT_OUT\")"
  fi
}

# Warm-engine extras — the only checks that need the premium engines installed. Gated behind
# WARBLE_REGRESSION_FULL=1 in a full run; an explicit --only warm runs them regardless.
check_warm() {
  require_bin || return
  WARM_ENGINE=$("$BIN" --engine 2>/dev/null)
  case "$WARM_ENGINE" in
    "Parakeet (warm)" | "Parakeet" | "whisper.cpp")
      ok "--engine reports a premium engine ($WARM_ENGINE)" ;;
    *)
      bad "--engine reports a premium engine (got \"$WARM_ENGINE\")" ;;
  esac
  step "--speak renders a real read-aloud" "\"$BIN\" --speak 'hello'"
}

# --- driver ----------------------------------------------------------------------------------

usage() {
  printf 'usage: sh scripts/regression.sh [--list] [--only <check>[,<check>…]]…\n'
  printf 'The full guide (coverage, seams, manual tests): docs/testing.md\n'
}

list_checks() {
  for c in $ALL_CHECKS; do printf '%-14s %s\n' "$c" "$(describe "$c")"; done
}

known_check() {
  for kc in $ALL_CHECKS; do [ "$kc" = "$1" ] && return 0; done
  return 1
}

run_check() {
  section "$1 — $(describe "$1")"
  "check_$(printf '%s' "$1" | tr '-' '_')"
}

ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) list_checks; exit 0 ;;
    --only)
      shift
      [ $# -gt 0 ] || { usage; exit 2; }
      ONLY="$ONLY $(printf '%s' "$1" | tr ',' ' ')" ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n\n' "$1"; usage; exit 2 ;;
  esac
  shift
done

for c in $ONLY; do
  if ! known_check "$c"; then
    printf 'unknown check: %s — the checks are:\n\n' "$c"
    list_checks
    exit 2
  fi
done

if [ -n "$ONLY" ]; then
  for c in $ONLY; do run_check "$c"; done
else
  for c in $ALL_CHECKS; do
    if [ "$c" = "warm" ] && [ "${WARBLE_REGRESSION_FULL:-}" != "1" ]; then
      printf '\n(warm-engine checks skipped — set WARBLE_REGRESSION_FULL=1 to include them)\n'
      continue
    fi
    run_check "$c"
    # A full run without a binary can't smoke anything — fail once, not once per check.
    if [ "$c" = "build" ] && [ ! -x "$BIN" ]; then
      printf '\nCLI checks skipped: no debug binary.\n'
      break
    fi
  done
fi

printf '\nregression: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
