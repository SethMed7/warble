#!/bin/sh
# warble regression — the single deterministic gate. Milestone 0.3+ checks extend THIS file.
#
# Runs, in order: the core acceptance suite (bun test) → a debug swift build → the headless CLI
# smokes with exact-output assertions. Engine-free by default: every check passes without the
# premium engines installed. WARBLE_REGRESSION_FULL=1 additionally exercises the warm-engine
# paths (premium --engine, a real --speak render). Exits 0 only when every check passed.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN="$ROOT/apps/macos/.build/debug/warble"
PASS=0
FAIL=0

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

summary() {
  printf '\nregression: %d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
}

# --- 1. core: the acceptance-tested cleaner (deterministic, no engines) ---------------------
section "core (bun test)"
if ( cd "$ROOT/core" && bun install --silent ); then
  ok "core: bun install"
  step "core: bun test" "cd \"$ROOT/core\" && bun test"
else
  bad "core: bun install"
  bad "core: bun test (skipped: install failed)"
fi

# --- 2. apps/macos: the debug build the smokes run against ----------------------------------
section "apps/macos (swift build)"
BUILD_OK=1
if ( cd "$ROOT/apps/macos" && swift build ); then
  ok "swift build (debug)"
else
  bad "swift build (debug)"
  BUILD_OK=0
fi
if [ "$BUILD_OK" -eq 0 ] || [ ! -x "$BIN" ]; then
  [ -x "$BIN" ] || bad "debug binary present at apps/macos/.build/debug/warble"
  printf '\nCLI smokes skipped: no fresh debug binary.\n'
  summary
fi

# --- 3. headless CLI smokes (engine-free, exact-output where deterministic) -----------------
section "CLI smokes (headless, engine-free)"

VERSION=$(plutil -extract CFBundleShortVersionString raw "$ROOT/apps/macos/Info.plist" 2>/dev/null)
if [ -n "$VERSION" ]; then
  expect "--version matches Info.plist ($VERSION)" "warble $VERSION" "$BIN" --version
else
  bad "read CFBundleShortVersionString from apps/macos/Info.plist"
fi

expect "--clean drops fillers and duplicates" "so the report" \
  "$BIN" --clean "um so the the report"

# Cleanup levels (ROADMAP 0.3). None must be verbatim; light must equal the deterministic --clean
# result; medium/high must degrade to the deterministic result with no LLM (WARBLE_DISABLE_LLM=1
# hides an installed one so this check is identical on every machine).
expect "--cleanup none returns input verbatim" "um so the the report" \
  "$BIN" --cleanup none "um so the the report"

CLEAN_OUT=$("$BIN" --clean "um so the the report" 2>/dev/null)
expect "--cleanup light equals --clean" "$CLEAN_OUT" \
  "$BIN" --cleanup light "um so the the report"

expect "--cleanup medium falls back deterministically (engine-free)" "so the report" \
  env WARBLE_DISABLE_LLM=1 "$BIN" --cleanup medium "um so the the report"

expect "--cleanup high falls back deterministically (engine-free)" "so the report" \
  env WARBLE_DISABLE_LLM=1 "$BIN" --cleanup high "um so the the report"

# The cleanup-level setting must round-trip through UserDefaults across processes, and the old
# "Polish with AI" preference must migrate (on → medium). The unbundled debug binary uses the
# "warble" defaults domain — NOT the installed app's io.github.sethmed7.voz — so this never
# touches real preferences; the prior level is still restored after.
ORIG_LEVEL=$("$BIN" --cleanup-level 2>/dev/null)
defaults delete warble cleanupLevel >/dev/null 2>&1
defaults write warble llmCleanupEnabled -bool true
expect "old polish-on preference migrates to medium" "medium" "$BIN" --cleanup-level
defaults delete warble llmCleanupEnabled >/dev/null 2>&1
expect "cleanup level defaults to light" "light" "$BIN" --cleanup-level
expect "--cleanup-level set prints the new level" "high" "$BIN" --cleanup-level high
expect "cleanup level round-trips through UserDefaults" "high" "$BIN" --cleanup-level
"$BIN" --cleanup-level "$ORIG_LEVEL" >/dev/null 2>&1  # restore whatever was set before

# A fixture dictionary makes --apply/--pronounce deterministic on any machine (the env var
# outranks the user's real dictionary; see Lexicon.fileURL / Pronouncer.fileURL).
DICT=$(mktemp "${TMPDIR:-/tmp}/warble-regression-dict.XXXXXX")
trap 'rm -f "$DICT"; rm -rf "$RHOME"' EXIT
printf '%s\n' '{"corrections":{"miele":"Myela"},"pronunciations":{"myela":"my-ell-uh"}}' > "$DICT"

expect "--apply uses the dictionary" "ship the Myela engine" \
  env WARBLE_DICTIONARY="$DICT" "$BIN" --apply "ship the miele engine"

expect "--pronounce uses the dictionary" "read my-ell-uh aloud" \
  env WARBLE_DICTIONARY="$DICT" "$BIN" --pronounce "read Myela aloud"

SELFTEST=$("$BIN" --selftest 2>&1)
if [ $? -eq 0 ] && printf '%s\n' "$SELFTEST" | grep -q "ALL PASS"; then
  ok "--selftest (ALL PASS)"
else
  bad "--selftest"
  printf '%s\n' "$SELFTEST"
fi

# Engine-free assertion: --engine must name a real tier ("Apple Speech" is the zero-install floor).
ENGINE=$("$BIN" --engine 2>/dev/null)
case "$ENGINE" in
  "Parakeet (warm)" | "Parakeet" | "whisper.cpp" | "Apple Speech")
    ok "--engine names a known engine ($ENGINE)" ;;
  *)
    bad "--engine names a known engine (got \"$ENGINE\")" ;;
esac

# Cause-naming errors (ROADMAP 0.3). --errors prints the whole taxonomy as "domain/reason: copy";
# asserting it verbatim makes any copy change deliberate. The WARBLE_FAULT seam (compiled into
# DEBUG builds only — this script always runs the debug binary) then forces the two failure paths
# provable headlessly: the engine-missing floor and a failed transcription.
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

# Long-session hardening (ROADMAP 0.3). The 20-minute cap and its warn-then-stop story resolve
# through HoldCap; --hold-cap prints the resolved numbers + the named stop cause exactly, and
# WARBLE_MAX_HOLD_SECS (a debug-build seam — this script runs the debug binary) compresses the
# cap so the machine runs in seconds. --hold-cap-sim then drives the REAL session clock
# (HoldCapClock) at a 4s cap: the countdown must tick before the cap fires (the binary exits
# non-zero if it didn't) and the run must end capped. Timing jitter only shifts the countdown
# values, so the assertion is structural (some warn tick + a final "capped"), not exact.
# What remains manual: holding Fn for 20 real minutes (the pill's visuals + the actual paste).
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

# Dictation recovery (ROADMAP 0.3 — "never lose a word"). Simulate an interrupted dictation
# headlessly: a sandbox store (WARBLE_HOME — the real ~/.warble is never touched) holding one
# orphaned in-flight WAV whose RIFF/data sizes are ZERO — exactly what a crash leaves, since
# AVAudioFile finalizes the header only on close. The scan must repair the header (or the clip
# reads as empty: 0.0s), and with WARBLE_FAULT=transcribe-fail forcing every engine to fail, the
# clip must land as a FAILED history event with the audio intact — engine-free and deterministic.
RHOME=$(mktemp -d "${TMPDIR:-/tmp}/warble-regression-home.XXXXXX")
mkdir -p "$RHOME/inflight"
ORPHAN="$RHOME/inflight/inflight-regression.wav"
{
  # 44-byte WAV header (16 kHz mono 16-bit PCM) with stale zero sizes + 32000 bytes = 1.0s audio.
  printf 'RIFF\0\0\0\0WAVEfmt '
  printf '\020\0\0\0\001\0\001\0\200\076\0\0\0\175\0\0\002\0\020\0'
  printf 'data\0\0\0\0'
  dd if=/dev/zero bs=8000 count=4 2>/dev/null
} > "$ORPHAN"
# Backdate it: files fresher than a few seconds are skipped as possibly-live recordings.
touch -t "$(date -v-5M +%Y%m%d%H%M.%S)" "$ORPHAN"

# The kept-audio gate reads the Save-recordings default; pin it to its default (on) for the check.
SAVE_AUDIO_ORIG=$(defaults read warble insightsSaveAudio 2>/dev/null)
defaults delete warble insightsSaveAudio >/dev/null 2>&1

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

if [ ! -e "$ORPHAN" ]; then
  ok "in-flight clip consumed after recovery"
else
  bad "in-flight clip consumed after recovery"
fi

expect "recovery scan is idempotent (no orphan left)" "no in-flight dictation found" \
  env WARBLE_HOME="$RHOME" "$BIN" --recover-scan

[ -n "$SAVE_AUDIO_ORIG" ] && defaults write warble insightsSaveAudio -int "$SAVE_AUDIO_ORIG" >/dev/null 2>&1

# --- 4. warm-engine paths (opt-in: needs the premium engines installed) ---------------------
if [ "${WARBLE_REGRESSION_FULL:-}" = "1" ]; then
  section "warm engines (WARBLE_REGRESSION_FULL=1)"
  case "$ENGINE" in
    "Parakeet (warm)" | "Parakeet" | "whisper.cpp")
      ok "--engine reports a premium engine ($ENGINE)" ;;
    *)
      bad "--engine reports a premium engine (got \"$ENGINE\")" ;;
  esac
  step "--speak renders a real read-aloud" "\"$BIN\" --speak 'hello'"
else
  printf '\n(warm-engine checks skipped — set WARBLE_REGRESSION_FULL=1 to include them)\n'
fi

summary
