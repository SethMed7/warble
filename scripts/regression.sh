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
ALL_CHECKS="core build unit version cleanup cleanup-level dictionary snippets autosend selftest engine errors hold-cap recovery retranscribe recover-raw bench onboarding practice setup-sizes setup-resume listening gallery warm"

describe() {
  case "$1" in
    core)          echo "core/ acceptance suite (bun install + bun test)" ;;
    build)         echo "swift build (debug) — the binary every CLI check runs" ;;
    unit)          echo "swift test — pure-logic unit tests (cleaner twin, spell-out, cap math, hallucination filter, onboarding machine, resume matrix, ping synthesis)" ;;
    version)       echo "--version matches Info.plist" ;;
    cleanup)       echo "cleanup levels: --clean + all four --cleanup levels, engine-free" ;;
    cleanup-level) echo "cleanup level persists across processes; old polish pref migrates" ;;
    dictionary)    echo "--apply/--pronounce over a fixture dictionary + learn-threshold promotion" ;;
    snippets)      echo "--expand over a fixture WARBLE_HOME: trigger-alone, in-sentence, no-snippets passthrough, dictionary+snippet order, 0600 storage" ;;
    autosend)      echo "--autosend: toggle off -> verbatim passthrough; toggle on -> final-position strip + send, mid-sentence untouched; the landed+sent pill renders" ;;
    selftest)      echo "--selftest: learn-from-edits detection + history-event codability" ;;
    engine)        echo "--engine names a known engine tier" ;;
    errors)        echo "cause-naming taxonomy verbatim + engine-missing / transcribe-fail faults" ;;
    hold-cap)      echo "session cap story resolves; compressed clock warns then stops cleanly" ;;
    recovery)      echo "orphaned in-flight clip -> FAILED history event, audio kept, idempotent" ;;
    retranscribe)  echo "FAILED event resolves in place on --retranscribe (stub engine)" ;;
    recover-raw)   echo "happy-path recovery persists the raw transcript (undo-polish in the store)" ;;
    bench)         echo "benchmark harness smoke: wer/stats tests, latency over the stub engine, footprint" ;;
    onboarding)    echo "onboarding flow: --onboarding-state declares the card flow; every card (+ variants) renders a real @2x PNG" ;;
    practice)      echo "practice sandbox: a rehearsal dictation shows raw -> cleaned but never lands in History/stats" ;;
    setup-sizes)   echo "engine setup: --engine-sizes states the verified size/destination table; every Setup card state renders a real @2x PNG" ;;
    setup-resume)  echo "engine setup: downloads resume a truncated .part, reuse a complete dest, restart on an ignored range — loopback fixture server, no external network" ;;
    listening)     echo "the listening contract: the sounds toggle round-trips (--sounds, default on); every pill state renders a real @2x PNG" ;;
    gallery)       echo "the card gallery: scripts/onboarding-gallery.sh renders every onboarding card, Setup state, and pill state in one command" ;;
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

# The fixture snippets home: WARBLE_HOME (unlike the dictionary's own env var) relocates the
# WHOLE store, so this is a directory containing snippets.json — see Snippets.fileURL.
SNIP_HOME="$REGTMP/snip-home"
mkdir -p "$SNIP_HOME"
printf '%s\n' '{"snippets":{"sign off":"Best,\nSeth","myela engine":"Myela Turbo Engine"}}' > "$SNIP_HOME/snippets.json"

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

# Pure-logic unit tests (apps/macos/Tests/): the BasicCleaner twin runs the SAME acceptance
# cases as core/clean.test.ts so the Swift/TS cleaners can't drift, plus SpellOut, HoldCap math,
# the hallucination filter, and the onboarding state machine (SharedTests: step gating, skip
# paths, first-run gate migration, post-update re-verify). Engine-free; shares swift build's
# artifacts.
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

# Snippets (ROADMAP 0.5): --expand over a fixture WARBLE_HOME. The matcher itself (word
# boundaries, longest-match, no recursion, case-insensitivity, multi-line) is unit-tested in
# `swift test` (SnippetsTests) against the pure static twin; this proves the headless flag, the
# storage seam, and — the one thing only an end-to-end check can prove — that the real pipeline
# order (cleanup -> dictionary -> snippets) is what actually runs.
check_snippets() {
  require_bin || return
  SIGNOFF_WANT=$(printf 'Best,\nSeth')
  expect "trigger spoken alone replaces the whole dictation" "$SIGNOFF_WANT" \
    env WARBLE_HOME="$SNIP_HOME" "$BIN" --expand "sign off"
  expect "trigger inside a longer dictation replaces only its span" "ship the Myela Turbo Engine home" \
    env WARBLE_HOME="$SNIP_HOME" "$BIN" --expand "ship the myela engine home"
  EMPTY_HOME="$REGTMP/snip-empty"
  mkdir -p "$EMPTY_HOME"
  expect "no snippets defined -> verbatim passthrough" "um so the the report" \
    env WARBLE_HOME="$EMPTY_HOME" "$BIN" --expand "um so the the report"

  # Dictionary + snippet interaction order: "miele" -> "Myela" (dictionary) must land BEFORE the
  # "myela engine" trigger is matched, so the real leg order (cleanup -> dictionary -> snippets)
  # is what a raw "miele" utterance actually gets.
  APPLIED=$(env WARBLE_DICTIONARY="$DICT" "$BIN" --apply "ship the miele engine home")
  EXPANDED=$(env WARBLE_HOME="$SNIP_HOME" "$BIN" --expand "$APPLIED")
  if [ "$EXPANDED" = "ship the Myela Turbo Engine home" ]; then
    ok "dictionary runs before snippets, so a corrected spelling can still trigger one"
  else
    bad "dictionary + snippet interaction order (dictionary=\"$APPLIED\"; expanded=\"$EXPANDED\")"
  fi
  # Negative control: the same trigger against the UNCORRECTED spelling must NOT fire — proof
  # that the positive result above isn't a coincidence of the fixture text.
  expect "the trigger does not fire before the dictionary corrects the spelling" "ship the miele engine home" \
    env WARBLE_HOME="$SNIP_HOME" "$BIN" --expand "ship the miele engine home"

  # Storage: the dashboard's Add/Save action (--snippet-set is its headless twin) writes an
  # owner-only file under WARBLE_HOME, and a later process reads the same entry back.
  SAVE_HOME="$REGTMP/snip-save"
  mkdir -p "$SAVE_HOME"
  env WARBLE_HOME="$SAVE_HOME" "$BIN" --snippet-set "my address" "123 Main St" >/dev/null 2>&1
  SNIP_FILE="$SAVE_HOME/snippets.json"
  SNIP_PERM=$(stat -f "%OLp" "$SNIP_FILE" 2>/dev/null || stat -c "%a" "$SNIP_FILE" 2>/dev/null)
  if [ -f "$SNIP_FILE" ] && [ "$SNIP_PERM" = "600" ]; then
    ok "snippets.json is written owner-only (0600), like the rest of ~/.warble"
  else
    bad "snippets.json owner-only permissions (file: $([ -f "$SNIP_FILE" ] && echo present || echo missing); perm: ${SNIP_PERM:-none})"
  fi
  expect "a snippet saved via the dashboard's Add path round-trips through --expand" "123 Main St" \
    env WARBLE_HOME="$SAVE_HOME" "$BIN" --expand "my address"
}

# "Press enter" auto-send (ROADMAP 0.5): --autosend proves the toggle gate plus the pure
# detector's final-position / mid-sentence / punctuation behavior through the real CLI (the
# matrix itself is also unit-tested directly in AutoSendTests, no process spawn there); the
# toggle's cross-process persistence uses the same "warble" defaults domain as
# --cleanup-level/--sounds, restored after. The landed+sent pill (the feedback that fires
# alongside a real send — DESIGN.md's "checkmark + text-hi text" success rule) renders and is
# provably wider than the textless landed pill, the same idiom check_listening uses.
check_autosend() {
  require_bin || return
  PIN_AUTOSEND=$(defaults read warble autoSendEnabled 2>/dev/null || true)

  defaults write warble autoSendEnabled -bool false
  AUTOSEND_OFF=$("$BIN" --autosend "ship the report press enter")
  if printf '%s\n' "$AUTOSEND_OFF" | grep -qx "send: no" \
    && printf '%s\n' "$AUTOSEND_OFF" | grep -qx "pasted: ship the report press enter"; then
    ok "toggle off -> verbatim passthrough even with the phrase (no hint, no strip)"
  else
    bad "toggle off -> verbatim passthrough (got: \"$AUTOSEND_OFF\")"
  fi

  defaults write warble autoSendEnabled -bool true
  AUTOSEND_ON=$("$BIN" --autosend "ship the report press enter")
  if printf '%s\n' "$AUTOSEND_ON" | grep -qx "send: yes" \
    && printf '%s\n' "$AUTOSEND_ON" | grep -qx "pasted: ship the report"; then
    ok "toggle on -> final-position phrase strips and reports send"
  else
    bad "toggle on -> strip + send (got: \"$AUTOSEND_ON\")"
  fi

  AUTOSEND_PUNCT=$("$BIN" --autosend "ship the report press enter.")
  if printf '%s\n' "$AUTOSEND_PUNCT" | grep -qx "send: yes" \
    && printf '%s\n' "$AUTOSEND_PUNCT" | grep -qx "pasted: ship the report"; then
    ok "trailing punctuation on the command is tolerated"
  else
    bad "trailing punctuation tolerated (got: \"$AUTOSEND_PUNCT\")"
  fi

  AUTOSEND_MID=$("$BIN" --autosend "please press enter and keep typing")
  if printf '%s\n' "$AUTOSEND_MID" | grep -qx "send: no" \
    && printf '%s\n' "$AUTOSEND_MID" | grep -qx "pasted: please press enter and keep typing"; then
    ok "mid-sentence occurrence is left verbatim, even with the toggle on"
  else
    bad "mid-sentence occurrence left verbatim (got: \"$AUTOSEND_MID\")"
  fi

  if [ -n "$PIN_AUTOSEND" ]; then
    defaults write warble autoSendEnabled -int "$PIN_AUTOSEND"
  else
    defaults delete warble autoSendEnabled >/dev/null 2>&1
  fi

  AS_DIR="$REGTMP/autosend-pill"
  mkdir -p "$AS_DIR"
  if "$BIN" --render-pill "landed+sent" "$AS_DIR/landed-sent.png" >/dev/null 2>&1 && [ -s "$AS_DIR/landed-sent.png" ]; then
    AS_W=$(sips -g pixelWidth "$AS_DIR/landed-sent.png" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    AS_H=$(sips -g pixelHeight "$AS_DIR/landed-sent.png" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    if [ "$AS_H" = "64" ] && [ "${AS_W:-0}" -gt 220 ]; then
      ok "pill state 'landed+sent' renders wider than the textless landed pill (${AS_W}x64 PNG)"
    else
      bad "pill state 'landed+sent' renders wider than landed (dims: ${AS_W:-none}x${AS_H:-none}, want >220 x64)"
    fi
  else
    bad "pill state 'landed+sent' renders a nonzero PNG"
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

# Onboarding (ROADMAP 0.4: permission cards + the guaranteed-first-success arc). The flow is a
# pure state machine (unit-tested in swift test); this check proves its two headless seams.
# --onboarding-state must declare the card flow in order; the mic/ax completion values are the
# machine's real permission state, so those assertions are structural (parseable line, yes|no)
# while the demonstrations (welcome/meter/finish) are constant-complete and asserted exactly —
# and practice/read must be constant-INCOMPLETE headlessly (their features only fire live). Then
# EVERY declared step must render offscreen to a real @2x PNG (--render-onboarding, a DEBUG seam;
# no window is shown, no permission is touched), plus every preview-state variant: the granted
# look of both permission cards, the meter/practice cards' skipped-mic look, the practice card's
# landed raw→cleaned transformation, and the read card's done/no-accessibility looks — sips
# confirms real 920×1080 pixels, so a blank or 1x render can't pass. Skip paths/migration/jump-
# back live in swift test; the by-hand walkthrough is in docs/testing.md.
check_onboarding() {
  require_bin || return
  OB_STATE=$("$BIN" --onboarding-state 2>/dev/null)
  OB_IDS=$(printf '%s\n' "$OB_STATE" | awk '{printf "%s ", $2}')
  if [ "$OB_IDS" = "welcome mic ax meter practice read finish " ]; then
    ok "--onboarding-state declares the 0.4 flow in order (welcome mic ax meter practice read finish)"
  else
    bad "--onboarding-state declares the 0.4 flow in order (got \"$OB_STATE\")"
  fi
  if [ -z "$(printf '%s\n' "$OB_STATE" | grep -v -E '^step [a-z-]+ complete=(yes|no) skippable=yes$')" ]; then
    ok "every step is parseable and skippable (the product law: every step skippable)"
  else
    bad "every step is parseable and skippable (got \"$OB_STATE\")"
  fi
  if printf '%s\n' "$OB_STATE" | grep -q '^step welcome complete=yes' \
    && printf '%s\n' "$OB_STATE" | grep -q '^step meter complete=yes' \
    && printf '%s\n' "$OB_STATE" | grep -q '^step finish complete=yes'; then
    ok "the demonstrations (welcome meter finish) are constant-complete (Next never gates on them)"
  else
    bad "the demonstrations are constant-complete (got \"$OB_STATE\")"
  fi
  if printf '%s\n' "$OB_STATE" | grep -q '^step practice complete=no' \
    && printf '%s\n' "$OB_STATE" | grep -q '^step read complete=no'; then
    ok "practice and read are incomplete headlessly (they complete only when the feature fires)"
  else
    bad "practice and read are incomplete headlessly (got \"$OB_STATE\")"
  fi
  OB_DIR="$REGTMP/onboarding"
  mkdir -p "$OB_DIR"
  for id in $(printf '%s\n' "$OB_STATE" | awk '{print $2}') \
    mic+granted ax+granted meter+nomic practice+done practice+nomic read+done read+noax; do
    OB_PNG="$OB_DIR/$id.png"
    if "$BIN" --render-onboarding "$id" "$OB_PNG" >/dev/null 2>&1 && [ -s "$OB_PNG" ]; then
      OB_DIMS=$(sips -g pixelWidth -g pixelHeight "$OB_PNG" 2>/dev/null | awk '/pixel/ {printf "%s ", $2}')
      if [ "$OB_DIMS" = "920 1080 " ]; then
        ok "card '$id' renders offscreen at 2x (920x1080 PNG)"
      else
        bad "card '$id' renders offscreen at 2x (dims: ${OB_DIMS:-none})"
      fi
    else
      bad "card '$id' renders a nonzero PNG"
    fi
  done
}

# The practice card's sandbox invariant (ROADMAP 0.4 "guaranteed first success"): a rehearsal
# dictation runs the REAL pipeline but must never land in History/stats. --practice-sim pushes a
# stub-engine transcription through the store's record gate twice — tagged sandbox first (nothing
# may move), then as the control dictation (must land, so a store that's simply broken can't fake
# a pass). WARBLE_HOME sandboxes the store; the final grep proves the invariant on disk, not just
# in memory. The flag-through-the-controller wiring (begin/deliver) is by-hand: docs/testing.md.
check_practice() {
  require_bin || return
  PHOME="$REGTMP/practice-home"
  rm -rf "$PHOME"
  pin_store_defaults
  pin_cleanup_level light
  PRACTICE_OUT=$(env WARBLE_HOME="$PHOME" WARBLE_FORCE_ENGINE=stub WARBLE_DISABLE_LLM=1 \
    "$BIN" --practice-sim "$ROOT/scripts/bench/fixtures/e2e-fixture.wav" 2>&1)
  PRACTICE_STATUS=$?
  restore_cleanup_level
  restore_store_defaults
  if [ "$PRACTICE_STATUS" -eq 0 ] \
    && printf '%s\n' "$PRACTICE_OUT" | grep -q "^raw: um so the the quick brown fox$" \
    && printf '%s\n' "$PRACTICE_OUT" | grep -q "^cleaned: so the quick brown fox$" \
    && printf '%s\n' "$PRACTICE_OUT" | grep -q "^sandbox: nothing recorded$" \
    && printf '%s\n' "$PRACTICE_OUT" | grep -q "^control: recorded$"; then
    ok "rehearsal shows raw → cleaned; sandbox records nothing, control records"
  else
    bad "rehearsal sandbox invariant (exit $PRACTICE_STATUS; got \"$PRACTICE_OUT\")"
  fi
  PRACTICE_COUNT=$(grep -c '"kind":"dictate"' "$PHOME/history.json" 2>/dev/null)
  if [ "$PRACTICE_COUNT" = "1" ]; then
    ok "history.json holds exactly the control event (the rehearsal left no line)"
  else
    bad "history.json holds exactly the control event (got ${PRACTICE_COUNT:-none})"
  fi
}

# Engine setup, part one (ROADMAP 0.4 "engine setup friction"): sizes up front. --engine-sizes
# must state the verified download/disk/destination table verbatim — the numbers were measured
# against the real artifacts (HTTP content-lengths + du of finished installs), so any drift is a
# deliberate re-verification, exactly like --errors. MEMEX_AI_HOME is pinned so the printed
# store paths are deterministic. Then every Setup card state must render offscreen to a real
# @2x PNG (--render-setup, a DEBUG seam): width is exact (1120 = 560pt @2x); height is the
# content's own (fixture text wraps differently per state and the Mac card shows the real
# machine), so it's asserted as "tall enough to hold the three cards", which a blank or 1x
# render can't fake.
check_setup_sizes() {
  require_bin || return
  SIZES_WANT='engine dictation | download ~510 MB | disk ~0.9 GB | weights ~/.memex/ai/models | runtime ~/.warble
engine voices | download ~140 MB + ~95 MB voices on first read | disk ~0.5 GB | weights ~/.memex/ai/models/kokoro | runtime ~/.warble/kokoro
engine cleanup | download ~0.9 GB | disk ~1.1 GB | weights ~/.memex/ai/models/qwen2.5-1.5b-instruct-4bit | runtime ~/.warble'
  expect "--engine-sizes states sizes + destinations up front (drift = re-verify the numbers)" \
    "$SIZES_WANT" env MEMEX_AI_HOME="$HOME/.memex/ai" "$BIN" --engine-sizes
  SETUP_DIR="$REGTMP/setup-renders"
  mkdir -p "$SETUP_DIR"
  for s in fresh installing installed failed; do
    SETUP_PNG="$SETUP_DIR/$s.png"
    if "$BIN" --render-setup "$s" "$SETUP_PNG" >/dev/null 2>&1 && [ -s "$SETUP_PNG" ]; then
      SETUP_W=$(sips -g pixelWidth "$SETUP_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
      SETUP_H=$(sips -g pixelHeight "$SETUP_PNG" 2>/dev/null | awk '/pixelHeight/ {print $2}')
      if [ "$SETUP_W" = "1120" ] && [ "${SETUP_H:-0}" -ge 1000 ]; then
        ok "setup state '$s' renders offscreen at 2x (1120x$SETUP_H PNG)"
      else
        bad "setup state '$s' renders offscreen at 2x (dims: ${SETUP_W:-none}x${SETUP_H:-none})"
      fi
    else
      bad "setup state '$s' renders a nonzero PNG"
    fi
  done
}

# Engine setup, part two: resumable downloads, proven byte-for-byte against a loopback fixture
# server (scripts/fixtures/range-server.ts — 127.0.0.1 only; the suite never touches the real
# network). The server logs every request's Range header, so the assertions read what actually
# went over the wire: a truncated <dest>.part resumes with "bytes=<n>-" and only the remainder
# transfers; a dest that already matches the remote size costs one HEAD and zero data; a
# full-length partial (crash between download and rename) is verified via 416+HEAD and promoted,
# never refetched; a server that ignores Range gets an honest restart. Partials live ONLY in
# .part files (never at dest), so engine detection can't mistake them for finished installs.
check_setup_resume() {
  require_bin || return
  RESUME_DIR="$REGTMP/resume"
  mkdir -p "$RESUME_DIR"
  awk 'BEGIN{for(i=0;i<32768;i++) printf "%08d", i}' > "$RESUME_DIR/fixture.bin" # 256 KiB, position-coded
  RLOG="$RESUME_DIR/req.log"; : > "$RLOG"
  bun "$ROOT/scripts/fixtures/range-server.ts" "$RESUME_DIR/fixture.bin" "$RLOG" > "$RESUME_DIR/port.txt" 2>&1 &
  RSRV_PID=$!
  RPORT=""
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    RPORT=$(sed -n 's/^port //p' "$RESUME_DIR/port.txt" 2>/dev/null)
    [ -n "$RPORT" ] && break
    sleep 0.25
  done
  if [ -z "$RPORT" ]; then
    bad "range fixture server starts (no port line; is bun installed?)"
    kill "$RSRV_PID" 2>/dev/null
    return
  fi
  RURL="http://127.0.0.1:$RPORT/fixture.bin"

  # 1. A fresh fetch lands the exact bytes and leaves no partial behind.
  R1=$("$BIN" --fetch-resume "$RURL" "$RESUME_DIR/dl1.bin" 2>&1)
  if [ $? -eq 0 ] && printf '%s\n' "$R1" | grep -q "^fetched 262144 bytes" \
    && cmp -s "$RESUME_DIR/fixture.bin" "$RESUME_DIR/dl1.bin" \
    && [ ! -e "$RESUME_DIR/dl1.bin.part" ]; then
    ok "fresh fetch lands the exact bytes; the .part is promoted, not copied"
  else
    bad "fresh fetch (got \"$R1\")"
  fi

  # 2. A truncated partial resumes: only the remainder crosses the wire (the log's Range proves it).
  dd if="$RESUME_DIR/fixture.bin" of="$RESUME_DIR/dl2.bin.part" bs=1024 count=100 2>/dev/null
  R2=$("$BIN" --fetch-resume "$RURL" "$RESUME_DIR/dl2.bin" 2>&1)
  if [ $? -eq 0 ] && printf '%s\n' "$R2" | grep -q "^resumed from 102400 bytes$" \
    && cmp -s "$RESUME_DIR/fixture.bin" "$RESUME_DIR/dl2.bin" \
    && grep -q "^GET bytes=102400-$" "$RLOG"; then
    ok "interrupted download resumes from its .part (server saw Range: bytes=102400-)"
  else
    bad "interrupted download resumes (got \"$R2\"; log: $(cat "$RLOG" 2>/dev/null | tr '\n' ' '))"
  fi

  # 3. A dest that already matches the remote size is never re-downloaded (one HEAD, no GET).
  cp "$RESUME_DIR/fixture.bin" "$RESUME_DIR/dl3.bin"
  R3=$("$BIN" --fetch-resume "$RURL" "$RESUME_DIR/dl3.bin" 2>&1)
  if [ $? -eq 0 ] && printf '%s\n' "$R3" | grep -q "^already complete (262144 bytes)" \
    && [ "$(tail -n 1 "$RLOG")" = "HEAD -" ]; then
    ok "complete dest is reused, not re-downloaded (one HEAD, zero data)"
  else
    bad "complete dest reuse (got \"$R3\"; log tail: $(tail -n 1 "$RLOG" 2>/dev/null))"
  fi

  # 4. A full-length partial (crash after the last byte, before the rename) is verified — 416 +
  #    HEAD — and promoted without refetching.
  cp "$RESUME_DIR/fixture.bin" "$RESUME_DIR/dl4.bin.part"
  R4=$("$BIN" --fetch-resume "$RURL" "$RESUME_DIR/dl4.bin" 2>&1)
  if [ $? -eq 0 ] && printf '%s\n' "$R4" | grep -q "^partial already held every byte" \
    && cmp -s "$RESUME_DIR/fixture.bin" "$RESUME_DIR/dl4.bin"; then
    ok "full-length partial verifies (416 + HEAD) and promotes without a refetch"
  else
    bad "full-length partial verify (got \"$R4\")"
  fi

  # 5. A server that ignores Range (sends 200) gets an honest restart — never corrupted appends.
  dd if="$RESUME_DIR/fixture.bin" of="$RESUME_DIR/dl5.bin.part" bs=1024 count=100 2>/dev/null
  R5=$("$BIN" --fetch-resume "http://127.0.0.1:$RPORT/noresume/fixture.bin" "$RESUME_DIR/dl5.bin" 2>&1)
  if [ $? -eq 0 ] && printf '%s\n' "$R5" | grep -q "^restarted — server ignored the range$" \
    && cmp -s "$RESUME_DIR/fixture.bin" "$RESUME_DIR/dl5.bin"; then
    ok "ignored range restarts the file honestly (no corrupt append)"
  else
    bad "ignored-range restart (got \"$R5\")"
  fi

  kill "$RSRV_PID" 2>/dev/null
  wait "$RSRV_PID" 2>/dev/null
}

# The listening contract (ROADMAP 0.4 — "it heard me", unambiguous). Two headless halves:
# (1) the start/stop pings' toggle must round-trip through UserDefaults across processes via
# --sounds — default ON (the ping is the contract), and once off it must STAY off (product.md
# §4.5: nothing re-enables itself). The pings themselves are synthesized pure math, unit-tested
# in swift test (SoundsTests); actually hearing them is a by-hand item in docs/testing.md.
# (2) every pill state must render offscreen to a real @2x PNG via --render-pill (DEBUG seam;
# no panel, no mic): the live listening waveform, the hover-revealed gesture hint, the cap
# countdown, the processing spinner, the landed checkmark, and the clipboard/error text pills.
# Wave-pill layouts carry no text, so their dims are asserted exactly; text-bearing states carry
# font-metric widths, so they assert height + "the extra content actually widened the pill".
check_listening() {
  require_bin || return
  PIN_SOUNDS=$(defaults read warble dictateSounds 2>/dev/null || true)
  defaults delete warble dictateSounds >/dev/null 2>&1
  expect "sounds default on (the ping is the contract)" "on" "$BIN" --sounds
  expect "--sounds off persists" "off" "$BIN" --sounds off
  expect "sounds stay off across processes (nothing re-enables itself)" "off" "$BIN" --sounds
  expect "--sounds on re-enables (the user's call, only ever the user's)" "on" "$BIN" --sounds on
  if [ -n "$PIN_SOUNDS" ]; then
    defaults write warble dictateSounds -int "$PIN_SOUNDS" >/dev/null 2>&1
  else
    defaults delete warble dictateSounds >/dev/null 2>&1
  fi

  PILL_DIR="$REGTMP/pill"
  mkdir -p "$PILL_DIR"
  # Fixed-layout states: exact pixel dims (the pill's arithmetic, at 2x).
  for spec in "listening 176" "processing 220" "landed 220" "copied 920"; do
    set -- $spec
    PILL_PNG="$PILL_DIR/$1.png"
    if "$BIN" --render-pill "$1" "$PILL_PNG" >/dev/null 2>&1 && [ -s "$PILL_PNG" ]; then
      PILL_DIMS=$(sips -g pixelWidth -g pixelHeight "$PILL_PNG" 2>/dev/null | awk '/pixel/ {printf "%s ", $2}')
      if [ "$PILL_DIMS" = "$2 64 " ]; then
        ok "pill state '$1' renders offscreen at 2x (${2}x64 PNG)"
      else
        bad "pill state '$1' renders offscreen at 2x (dims: ${PILL_DIMS:-none}, want $2 64)"
      fi
    else
      bad "pill state '$1' renders a nonzero PNG"
    fi
  done
  # Text-bearing states: height exact; width must exceed the state's textless base, proving the
  # hint/countdown/copy actually joined the capsule.
  for spec in "listening+hint 176" "listening+cap 176" "processing+hint 220" "error 240"; do
    set -- $spec
    PILL_PNG="$PILL_DIR/$1.png"
    if "$BIN" --render-pill "$1" "$PILL_PNG" >/dev/null 2>&1 && [ -s "$PILL_PNG" ]; then
      PILL_W=$(sips -g pixelWidth "$PILL_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
      PILL_H=$(sips -g pixelHeight "$PILL_PNG" 2>/dev/null | awk '/pixelHeight/ {print $2}')
      if [ "$PILL_H" = "64" ] && [ "${PILL_W:-0}" -gt "$2" ]; then
        ok "pill state '$1' renders wider than its base (${PILL_W}x64 PNG)"
      else
        bad "pill state '$1' renders wider than its base (dims: ${PILL_W:-none}x${PILL_H:-none}, want >$2 x64)"
      fi
    else
      bad "pill state '$1' renders a nonzero PNG"
    fi
  done
}

# The card gallery (0.4, consolidated): scripts/onboarding-gallery.sh is the one command a human
# runs for design review — every onboarding card (+ variants), Setup state, and pill state as
# @2x PNGs. This check runs the real script into a sandbox dir and recomputes the expected count
# from the same sources the script uses (the machine's declared steps + the fixed variant/setup/
# pill lists), so a new card that misses the gallery — or a render seam that breaks — fails the
# gate, not the human's review.
check_gallery() {
  require_bin || return
  GAL_DIR="$REGTMP/gallery"
  GAL_OUT=$(sh "$ROOT/scripts/onboarding-gallery.sh" "$GAL_DIR" 2>&1)
  GAL_STATUS=$?
  GAL_STEPS=$("$BIN" --onboarding-state 2>/dev/null | grep -c '^step ')
  GAL_WANT=$((GAL_STEPS + 7 + 4 + 9)) # steps + onboarding variants + setup states + pill states
  GAL_GOT=$(ls "$GAL_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
  if [ "$GAL_STATUS" -eq 0 ] && [ "$GAL_GOT" = "$GAL_WANT" ] \
    && printf '%s\n' "$GAL_OUT" | grep -q "^gallery: $GAL_WANT/$GAL_WANT renders"; then
    ok "onboarding-gallery.sh renders every card/state in one command ($GAL_GOT PNGs)"
  else
    bad "onboarding-gallery.sh renders every card/state (exit $GAL_STATUS; want $GAL_WANT PNGs, got ${GAL_GOT:-0}; out: \"$GAL_OUT\")"
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
