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
ALL_CHECKS="core build unit version cleanup cleanup-level dictionary snippets autosend bindings readback context context-apply context-inspect retention selftest engine errors hold-cap recovery retranscribe recover-raw bench onboarding practice setup-sizes setup-resume listening gallery warm"

describe() {
  case "$1" in
    core)          echo "core/ acceptance suite (bun install + bun test)" ;;
    build)         echo "swift build (debug) — the binary every CLI check runs" ;;
    unit)          echo "swift test — pure-logic unit tests (cleaner twin, spell-out, cap math, hallucination filter, onboarding machine, resume matrix, ping synthesis, read-back availability, context-awareness gates/caps, corrections-count, WPM/human-units/heatmap retention math)" ;;
    version)       echo "--version matches Info.plist" ;;
    cleanup)       echo "cleanup levels: --clean + all four --cleanup levels, engine-free" ;;
    cleanup-level) echo "cleanup level persists across processes; old polish pref migrates" ;;
    dictionary)    echo "--apply/--pronounce over a fixture dictionary + learn-threshold promotion" ;;
    snippets)      echo "--expand over a fixture WARBLE_HOME: trigger-alone, in-sentence, no-snippets passthrough, dictionary+snippet order, 0600 storage" ;;
    autosend)      echo "--autosend: toggle off -> verbatim passthrough; toggle on -> final-position strip + send, mid-sentence untouched, secure field never sends; the landed+sent pill renders" ;;
    bindings)      echo "--bindings: default = Fn only; adds persist via the defaults seam + add/remove; conflicts/reserved rejected with a plain reason; invalid entries dropped on load" ;;
    readback)      echo "--readback-state: the availability story (landed -> available/expired/consumed; speak-off + secure-field gates); the landed+readback pill renders" ;;
    context)       echo "--context-sim: context awareness defaults OFF (nothing read); on -> bounded capture (last 200 words, 12-word preview note); a secure field captures nothing; off stays off" ;;
    context-apply) echo "--clean-in-context: per-category tone (editor/chat drop a short one-liner's trailing period; mail/document unchanged); context off = pre-0.6 goldens at every level; dictionary+snippets outrank tone" ;;
    context-inspect) echo "the inspect half: a committed pre-0.6 fixture still decodes in full (--history-count), a legacy dictation's History detail renders with no context row and a context-bearing one renders with it (--render-history), and Clear history removes the context record along with everything else" ;;
    retention)     echo "dashboard retention pass: --corrections-count on fixture text, a seeded correctionsCleaned round-trips (--history-count), --learned-count decodes a hand-planted visible-learning fixture and Clear history wipes it too, and Home + the share card render real PNGs for both an empty and a populated WARBLE_HOME" ;;
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

  # The secure-field gate claim (product.md security-adjacent principle): with the toggle ON and
  # the phrase said, a secure (password) field must still get NO Return keystroke — the phrase is
  # stripped from the pasted text regardless (that's cleanup, not sending), only the keystroke
  # itself is withheld. --secure exercises DictateController.deliver's exact gate
  # (AutoSend.mayFireReturn), unit-tested directly in AutoSendTests; a REAL secure system field is
  # by-hand (docs/testing.md).
  AUTOSEND_SECURE=$("$BIN" --autosend "ship the report press enter" --secure)
  if printf '%s\n' "$AUTOSEND_SECURE" | grep -qx "send: no" \
    && printf '%s\n' "$AUTOSEND_SECURE" | grep -qx "pasted: ship the report"; then
    ok "a secure field never sends, even with the toggle on and the phrase said (text still strips)"
  else
    bad "secure field never sends (got: \"$AUTOSEND_SECURE\")"
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

# Multi-shortcut + mouse bindings (ROADMAP 0.5): --bindings prints the active trigger table —
# the built-in Fn row (law, not storage) plus each persisted binding. The default is Fn only; a
# binding seeded with a plain `defaults write` (the seam the check uses) shows up in the next
# process's table; `add`/`remove` are the dashboard editor's headless twins (same validation
# path); a duplicate, a reserved key (Esc), a click button (mouse-2), and the 4th-slot add are
# each rejected with their plain reason and a non-zero exit; a hand-planted invalid array is
# dropped entry-by-entry on load, so the defaults seam can never wedge the tap. The model's pure
# halves (parse/validate/decode, event-matching key codes) are unit-tested in `swift test`
# (BindingsTests, incl. the monitor-teardown assertion); real key/mouse events are by-hand
# (docs/testing.md). Uses the "warble" defaults domain like --cleanup-level; pinned and restored.
check_bindings() {
  require_bin || return
  PIN_BINDINGS=$(defaults read warble dictateBindings 2>/dev/null || true)
  defaults delete warble dictateBindings >/dev/null 2>&1

  FN_ROW="fn hold+double-tap (built in)"
  expect "default binding table is Fn only (built in, not stored)" "$FN_ROW" "$BIN" --bindings

  defaults write warble dictateBindings -array "right-command:hold"
  expect "a binding seeded via the defaults seam shows in the next process's table" \
    "$(printf '%s\nright-command hold' "$FN_ROW")" "$BIN" --bindings

  expect "--bindings add persists a second binding (the dashboard's Add, headless)" \
    "added mouse-4 double-tap" "$BIN" --bindings add "mouse-4:double-tap"
  expect "the added binding round-trips across processes" \
    "$(printf '%s\nright-command hold\nmouse-4 double-tap' "$FN_ROW")" "$BIN" --bindings

  BIND_DUP=$("$BIN" --bindings add "right-command:hold" 2>/dev/null)
  if [ $? -ne 0 ] && printf '%s\n' "$BIND_DUP" | grep -q "^rejected: .*already bound"; then
    ok "a duplicate add is rejected with a plain reason"
  else
    bad "duplicate add rejected (got \"$BIND_DUP\")"
  fi

  BIND_ESC=$("$BIN" --bindings add "esc:hold" 2>/dev/null)
  if [ $? -ne 0 ] && printf '%s\n' "$BIND_ESC" | grep -q "^rejected: Esc cancels a dictation"; then
    ok "Esc is rejected as a trigger (it's the cancel key) with a plain reason"
  else
    bad "Esc rejected as a trigger (got \"$BIND_ESC\")"
  fi

  BIND_CLICK=$("$BIN" --bindings add "mouse-2:hold" 2>/dev/null)
  if [ $? -ne 0 ] && printf '%s\n' "$BIND_CLICK" | grep -q "^rejected: mouse buttons 1 and 2"; then
    ok "the Mac's own click buttons are rejected with a plain reason"
  else
    bad "click buttons rejected (got \"$BIND_CLICK\")"
  fi

  "$BIN" --bindings add "f13:hold" >/dev/null 2>&1 # the third and last slot
  BIND_CAP=$("$BIN" --bindings add "f14:hold" 2>/dev/null)
  if [ $? -ne 0 ] && printf '%s\n' "$BIND_CAP" | grep -q "^rejected: up to 3 bindings besides Fn"; then
    ok "a fourth binding is rejected at the cap with a plain reason"
  else
    bad "fourth binding rejected at the cap (got \"$BIND_CAP\")"
  fi

  expect "--bindings remove retires a binding" "removed f13 hold" "$BIN" --bindings remove "f13:hold"
  expect "the removal round-trips across processes" \
    "$(printf '%s\nright-command hold\nmouse-4 double-tap' "$FN_ROW")" "$BIN" --bindings

  defaults write warble dictateBindings -array "garbage" "mouse-2:hold" "f5:hold" "esc:hold"
  expect "invalid entries planted in defaults are dropped on load (table degrades to Fn only)" \
    "$FN_ROW" "$BIN" --bindings

  if [ -n "$PIN_BINDINGS" ]; then
    defaults write warble dictateBindings "$PIN_BINDINGS" >/dev/null 2>&1
  else
    defaults delete warble dictateBindings >/dev/null 2>&1
  fi
}

# Dictate → read-back proofread (ROADMAP 0.5): one keystroke after a dictation lands reads it
# back through the normal read-aloud pipeline. The availability machine's whole story — landed →
# available (⌃R armed) → expired/consumed (released), plus the per-mode gate (read-aloud off →
# ⌃R never arms) AND the secure-field gate (a secure-field landing never arms, even with
# read-aloud on — ReadBackAvailability.landed's `secure` parameter, the unit-tested twin of
# DictateController's ctx.secure check) — is printed by the REAL machine via --readback-state and
# asserted verbatim (the machine itself is also unit-tested in swift test, ReadBackTests). Stats
# honesty is by construction: a read-back routes through the Speak module's one-shot pipeline,
# whose single onRead callback is the only Insights logging path — one read event per read-back,
# never two. The landed pill's "⌃R to hear it back" affordance renders via --render-pill
# landed+readback and must out-width the textless landed base (the check_listening idiom). The
# live transient ⌃R claim and the actual read (with a REAL secure system field) are by-hand:
# docs/testing.md.
check_readback() {
  require_bin || return
  READBACK_WANT='grace 15s
landed (speak on) -> available · ⌃R armed
+15s -> expired · ⌃R released
landed again -> available · ⌃R armed
⌃R -> consumed · read fired once · ⌃R released
⌃R again -> nothing (already consumed)
landed (speak off) -> idle · ⌃R never armed
landed (secure field) -> idle · ⌃R never armed'
  expect "--readback-state tells the availability story (landed/expired/consumed/mode-off)" \
    "$READBACK_WANT" "$BIN" --readback-state

  RB_DIR="$REGTMP/readback-pill"
  mkdir -p "$RB_DIR"
  if "$BIN" --render-pill "landed+readback" "$RB_DIR/landed-readback.png" >/dev/null 2>&1 && [ -s "$RB_DIR/landed-readback.png" ]; then
    RB_W=$(sips -g pixelWidth "$RB_DIR/landed-readback.png" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    RB_H=$(sips -g pixelHeight "$RB_DIR/landed-readback.png" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    if [ "$RB_H" = "64" ] && [ "${RB_W:-0}" -gt 220 ]; then
      ok "pill state 'landed+readback' renders wider than the textless landed pill (${RB_W}x64 PNG)"
    else
      bad "pill state 'landed+readback' renders wider than landed (dims: ${RB_W:-none}x${RB_H:-none}, want >220 x64)"
    fi
  else
    bad "pill state 'landed+readback' renders a nonzero PNG"
  fi
}

# Local-only context awareness (ROADMAP 0.6 — the capture half, the Wispr scandal inverted).
# OFF by default, and the default is the load-bearing assertion: a fresh machine must print
# "context: off — nothing read" with NO setup. On, the capture is bounded: the word cap keeps the
# LAST 200 words (nearest the cursor), the category is derived locally (a static bundle-id map +
# keyword fallback, unit-tested), and what would persist is only the compact note — app, category,
# word count, ≤12-word preview, never the full text (the cap is structural: ContextRecord's only
# initializer derives the preview; asserted in swift test, ContextAwarenessTests). A secure
# (password) field captures NOTHING at all, even with the toggle on (--secure, the --autosend
# idiom). Off again must STAY off across processes (product.md §4.5 — nothing re-enables itself).
# The fixture file stands in for the AX-read text (real AX needs a live focused app — that pass is
# by-hand, docs/testing.md); the toggle round-trips through the same "warble" defaults domain as
# --sounds/--autosend, pinned and restored. Precision (product.md §4.9): captured context is never
# handed to any network-capable code path — its only consumers are DictateController → the
# in-memory DictationContext → InsightStore's bounded ContextRecord — and the Dictate module's
# only network I/O is the loopback link to warble's own local engines.
check_context() {
  require_bin || return
  PIN_CONTEXT=$(defaults read warble contextAwareness 2>/dev/null || true)
  defaults delete warble contextAwareness >/dev/null 2>&1

  CTX_FIX="$REGTMP/context-fixture.txt"
  awk 'BEGIN{for(i=1;i<=250;i++) printf "w%03d ", i}' > "$CTX_FIX"

  expect "context awareness defaults OFF — nothing read, no setup (the load-bearing negative)" \
    "context: off — nothing read" "$BIN" --context-sim com.apple.mail "$CTX_FIX"

  defaults write warble contextAwareness -bool true
  CTX_PREVIEW="preview: w051 w052 w053 w054 w055 w056 w057 w058 w059 w060 w061 w062…"
  expect "toggle on -> bounded capture: the last 200 words kept, a 12-word preview note" \
    "$(printf 'captured: app=com.apple.mail category=mail words=200\n%s' "$CTX_PREVIEW")" \
    "$BIN" --context-sim com.apple.mail "$CTX_FIX"
  expect "the app category is derived locally (a terminal reads as editor)" \
    "$(printf 'captured: app=com.googlecode.iterm2 category=editor words=200\n%s' "$CTX_PREVIEW")" \
    "$BIN" --context-sim com.googlecode.iterm2 "$CTX_FIX"

  expect "a secure field captures NOTHING at all, even with the toggle on" \
    "context: secure field — nothing read" "$BIN" --context-sim com.apple.mail "$CTX_FIX" --secure

  defaults write warble contextAwareness -bool false
  expect "off stays off across processes (§4.5 — nothing re-enables itself)" \
    "context: off — nothing read" "$BIN" --context-sim com.apple.mail "$CTX_FIX"

  if [ -n "$PIN_CONTEXT" ]; then
    defaults write warble contextAwareness -int "$PIN_CONTEXT" >/dev/null 2>&1
  else
    defaults delete warble contextAwareness >/dev/null 2>&1
  fi
}

# Context awareness — the APPLY half (ROADMAP 0.6): the captured category shapes output
# deterministically, and NOT capturing one is provably free. Two claims:
# (1) THE GOLDEN NO-CHANGE: with context off (the default), a fixed input set through every
#     cleanup level is byte-identical to the goldens below, which were generated from the
#     pre-apply binary (commit de5ee39) — the tone rules are additive and gated on category, so
#     nobody's output moves until they opt in AND a category is captured. WARBLE_DISABLE_LLM=1
#     keeps medium/high deterministic on any machine; even the toggle flipped ON must not change
#     a headless --cleanup (only a live capture carries a category).
# (2) PER-CATEGORY RULES via --clean-in-context (the exact BasicCleaner call the live path makes):
#     editor/terminal and chat drop the ASR's trailing period on a short one-liner (technical
#     dots like "main.py" are not sentence boundaries; ! and ? always stay; prose over the cap
#     keeps its period); mail/document keep full punctuation; `other` is byte-identical to
#     --clean. Casing and contractions are never touched (the identifier-casing case).
#     PRECEDENCE: the dictionary and snippets run AFTER the cleaner in the real leg order
#     (cleanup -> dictionary -> snippets, transcribeAndDeliver), so a learned casing and a
#     snippet's own trailing period always survive the tone pass — proven end to end here.
# The rules are unit-tested twin-for-twin (clean.test.ts + BasicCleanerTests); the LLM hint's
# prompt golden (nil/other -> the base prompt byte-identical) and the None-level verbatim gate
# are unit-tested in ContextAwarenessTests. Real per-app dogfood is by-hand (docs/testing.md).
check_context_apply() {
  require_bin || return
  PIN_CONTEXT=$(defaults read warble contextAwareness 2>/dev/null || true)
  defaults delete warble contextAwareness >/dev/null 2>&1

  # (1) the golden no-change: input|deterministic-golden pairs. "none" must be the input
  # verbatim; light/medium/high must all equal the pre-apply deterministic golden.
  while IFS='|' read -r G_IN G_WANT; do
    expect "context off: --cleanup none stays verbatim (\"$G_IN\")" "$G_IN" \
      env WARBLE_DISABLE_LLM=1 "$BIN" --cleanup none "$G_IN"
    for G_LEVEL in light medium high; do
      expect "context off: --cleanup $G_LEVEL matches the pre-apply golden (\"$G_IN\")" "$G_WANT" \
        env WARBLE_DISABLE_LLM=1 "$BIN" --cleanup "$G_LEVEL" "$G_IN"
    done
  done <<'GOLDENS'
git status.|git status.
on my way.|on my way.
um so the the report|so the report
can't wait, it's gonna be great.|can't wait, it's gonna be great.
npm install leftPad.|npm install leftPad.
Ship it Friday. I mean Monday.|Ship it Monday.
GOLDENS
  defaults write warble contextAwareness -bool true
  expect "the toggle alone changes nothing — only a live capture carries a category" \
    "git status." env WARBLE_DISABLE_LLM=1 "$BIN" --cleanup light "git status."
  defaults delete warble contextAwareness >/dev/null 2>&1

  # (2) the per-category rules, through the real CLI.
  expect "editor: a short command drops the ASR's trailing period" "git status" \
    "$BIN" --clean-in-context editor "git status."
  expect "editor: technical dots are not sentence boundaries" "run main.py" \
    "$BIN" --clean-in-context editor "run main.py."
  expect "editor: identifier casing survives — no sentence-case forcing" "npm install leftPad" \
    "$BIN" --clean-in-context editor "npm install leftPad."
  expect "editor: prose over the short-command cap keeps its period" \
    "this function returns the number of retries we allow." \
    "$BIN" --clean-in-context editor "this function returns the number of retries we allow."
  expect "chat: a short message drops the trailing period" "on my way" \
    "$BIN" --clean-in-context chat "on my way."
  expect "chat: ! and ? carry intent and stay" "on my way!" \
    "$BIN" --clean-in-context chat "on my way!"
  expect "chat: a multi-sentence message keeps its final period" "be there soon. save me a seat." \
    "$BIN" --clean-in-context chat "be there soon. save me a seat."
  expect "chat: contractions pass through untouched" "can't wait, it's gonna be great" \
    "$BIN" --clean-in-context chat "can't wait, it's gonna be great."
  expect "mail keeps full punctuation (current behavior)" "on my way." \
    "$BIN" --clean-in-context mail "on my way."
  expect "document keeps full punctuation (current behavior)" "on my way." \
    "$BIN" --clean-in-context document "on my way."
  expect "'other' is byte-identical to --clean" "$("$BIN" --clean "git status.")" \
    "$BIN" --clean-in-context other "git status."

  # PRECEDENCE: dictionary casing and snippet text outrank tone rules (they run after the
  # cleaner), chained through the same CLI legs the pipeline runs.
  TONED=$("$BIN" --clean-in-context editor "ship the miele engine.")
  APPLIED=$(env WARBLE_DICTIONARY="$DICT" "$BIN" --apply "$TONED")
  EXPANDED=$(env WARBLE_HOME="$SNIP_HOME" "$BIN" --expand "$APPLIED")
  if [ "$TONED" = "ship the miele engine" ] && [ "$EXPANDED" = "ship the Myela Turbo Engine" ]; then
    ok "dictionary casing + snippet expansion outrank the editor tone pass (leg order proven)"
  else
    bad "dictionary/snippets outrank tone rules (toned=\"$TONED\"; expanded=\"$EXPANDED\")"
  fi
  # A snippet whose saved text ENDS in a period: the tone strip ran before expansion, so the
  # snippet's own period lands untouched even in a chat.
  TONE_SNIP_HOME="$REGTMP/tone-snip"
  mkdir -p "$TONE_SNIP_HOME"
  env WARBLE_HOME="$TONE_SNIP_HOME" "$BIN" --snippet-set "done stamp" "Done." >/dev/null 2>&1
  TONED_TRIGGER=$("$BIN" --clean-in-context chat "done stamp.")
  expect "a snippet's own trailing period survives the chat tone pass (snippets run after)" "Done." \
    env WARBLE_HOME="$TONE_SNIP_HOME" "$BIN" --expand "$TONED_TRIGGER"

  if [ -n "$PIN_CONTEXT" ]; then
    defaults write warble contextAwareness -int "$PIN_CONTEXT" >/dev/null 2>&1
  else
    defaults delete warble contextAwareness >/dev/null 2>&1
  fi
}

# Context awareness — the INSPECT half (ROADMAP 0.6): the trust half. What was read must always be
# visible, Codable backward compatibility must hold (0.3-0.5 history.json lines predate `context`
# entirely and must still decode), and Clear history must take context records with it (they live
# on DictationEvent, so wiping history wipes them too). Three claims, all against the REAL store
# (WARBLE_HOME) and the REAL view (DictationDetailView), via two DEBUG seams:
#   --history-count     how many lines InsightStore actually decoded off disk (a malformed/rejected
#                        line would come up short — the decode-compat proof)
#   --render-history     rasterizes the NEWEST event's History detail exactly as the dashboard would
#                        show it (context row present/absent, formatting) — dims asserted here;
#                        content is eyeballed by hand against DESIGN.md (mist, no accent, no box)
# The record→display formatting itself (truncation, missing fields, the singular/plural word count,
# the app-name/bundle-id/"unknown" fallback) is unit-tested (swift test, ContextAwarenessTests); this
# check proves the wiring end to end, not the formatting rules again.
check_context_inspect() {
  require_bin || return

  # (1) decode-compat: the COMMITTED pre-0.6 fixture (three real 0.3-0.5 shapes — the bare original,
  # a FAILED-status recovery-era line, and an undo-polish line with `raw` — none carry `context`)
  # must decode in full, through the real store.
  LEGACY_HOME="$REGTMP/context-inspect-legacy"
  mkdir -p "$LEGACY_HOME"
  cp "$ROOT/scripts/fixtures/history-legacy.jsonl" "$LEGACY_HOME/history.json"
  LEGACY_LINES=$(wc -l < "$ROOT/scripts/fixtures/history-legacy.jsonl" | tr -d ' ')
  expect "the committed pre-0.6 fixture ($LEGACY_LINES lines, no context field) decodes in full" \
    "$LEGACY_LINES" env WARBLE_HOME="$LEGACY_HOME" "$BIN" --history-count

  HI_DIR="$REGTMP/history-renders"
  mkdir -p "$HI_DIR"
  LEGACY_PNG="$HI_DIR/legacy.png"
  if env WARBLE_HOME="$LEGACY_HOME" "$BIN" --render-history "$LEGACY_PNG" >/dev/null 2>&1 && [ -s "$LEGACY_PNG" ]; then
    LEGACY_W=$(sips -g pixelWidth "$LEGACY_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    LEGACY_H=$(sips -g pixelHeight "$LEGACY_PNG" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    if [ "$LEGACY_W" = "1480" ] && [ "${LEGACY_H:-0}" -ge 900 ]; then
      ok "a legacy (pre-0.6) dictation renders its History detail with no context row (1480x$LEGACY_H PNG)"
    else
      bad "legacy History detail renders offscreen at 2x (dims: ${LEGACY_W:-none}x${LEGACY_H:-none})"
    fi
  else
    bad "legacy History detail renders a nonzero PNG"
  fi

  # (2) a context-bearing (modern) line renders its History detail WITH the quiet context row —
  # hand-planted like make_orphan's WAV: the exact shape InsightStore.record() would have written.
  CTX_HOME="$REGTMP/context-inspect-modern"
  mkdir -p "$CTX_HOME"
  printf '%s\n' '{"id":"ctx-modern","ts":1799800000,"day":"2026-07-11","text":"following up on the q3 numbers now","words":7,"durationMs":2900,"appBundleId":"com.apple.mail","appName":"Mail","engine":"parakeet","kind":"dictate","context":{"app":"Mail","category":"mail","words":42,"preview":"Re: the Q3 numbers are in and they look good for the…"}}' \
    > "$CTX_HOME/history.json"
  expect "a context-bearing history line decodes" "1" env WARBLE_HOME="$CTX_HOME" "$BIN" --history-count

  CTX_PNG="$HI_DIR/context.png"
  if env WARBLE_HOME="$CTX_HOME" "$BIN" --render-history "$CTX_PNG" >/dev/null 2>&1 && [ -s "$CTX_PNG" ]; then
    CTX_W=$(sips -g pixelWidth "$CTX_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    CTX_H=$(sips -g pixelHeight "$CTX_PNG" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    if [ "$CTX_W" = "1480" ] && [ "${CTX_H:-0}" -ge 900 ]; then
      ok "a context-bearing dictation renders its History detail with the context row (1480x$CTX_H PNG)"
    else
      bad "context-bearing History detail renders offscreen at 2x (dims: ${CTX_W:-none}x${CTX_H:-none})"
    fi
  else
    bad "context-bearing History detail renders a nonzero PNG"
  fi

  # (3) Clear history takes the context record with it — it lives on DictationEvent, so clearing
  # the whole store must clear it too. Reuses the modern context-bearing home.
  expect "clear-history reports the one context-bearing event it removed" "cleared 1 event" \
    env WARBLE_HOME="$CTX_HOME" "$BIN" --clear-history
  if [ ! -e "$CTX_HOME/history.json" ]; then
    ok "history.json (and its context record) is gone after Clear history"
  else
    bad "history.json (and its context record) is gone after Clear history"
  fi
  expect "the store is empty after Clear history" "0" \
    env WARBLE_HOME="$CTX_HOME" "$BIN" --history-count
}

# The dashboard retention pass (ROADMAP 0.6): WPM vs typing averages, "corrections cleaned",
# human-unit word counts, and the streak heatmap are pure math proven in swift test
# (BasicCleanerTests/RetentionTests) — this check proves the LIVE WIRING: the counting/decoding
# CLI seams, and that Home + the share card render real PNGs for both an empty and a populated
# WARBLE_HOME (the "flow" layer, same split as every other 0.6 check).
check_retention() {
  require_bin || return

  # (1) --corrections-count: deterministic and engine-free over fixed fixture text — the exact
  # cases asserted in swift test (BasicCleanerTests), re-proven through the CLI seam.
  expect "corrections-count is 0 for already-clean text" "0" \
    "$BIN" --corrections-count "clean text with no fillers"
  expect "corrections-count sums fillers + a false start + a duplicate" "3" \
    "$BIN" --corrections-count "um so like like I was thinking uh maybe we ship it"

  # (2) correctionsCleaned rides the history line — a seeded value must not be rejected by the
  # decoder (the same "still decodes" proof context-inspect uses for the `context` field).
  CC_HOME="$REGTMP/retention-corrections"
  mkdir -p "$CC_HOME"
  printf '%s\n' '{"id":"cc1","ts":1,"day":"2026-07-11","text":"ship it","words":2,"durationMs":900,"engine":"test","kind":"dictate","correctionsCleaned":2}' \
    > "$CC_HOME/history.json"
  expect "a correctionsCleaned-bearing history line decodes" "1" \
    env WARBLE_HOME="$CC_HOME" "$BIN" --history-count

  # (3) Visible learning: --learned-count decodes a hand-planted learned.json fixture line (the
  # exact shape InsightStore.recordLearned would have written), and Clear history wipes it along
  # with everything else (product.md §4.8 — local data is also a privacy surface).
  LEARN_HOME="$REGTMP/retention-learned"
  mkdir -p "$LEARN_HOME"
  printf '%s\n' '{"id":"l1","ts":1,"word":"Myela","from":"miele"}' > "$LEARN_HOME/learned.json"
  touch "$LEARN_HOME/history.json"
  expect "a hand-planted learned.json line decodes" "1" \
    env WARBLE_HOME="$LEARN_HOME" "$BIN" --learned-count
  env WARBLE_HOME="$LEARN_HOME" "$BIN" --clear-history >/dev/null
  if [ ! -e "$LEARN_HOME/learned.json" ]; then
    ok "learned.json is gone after Clear history"
  else
    bad "learned.json is gone after Clear history"
  fi
  expect "learned-count is 0 after Clear history" "0" \
    env WARBLE_HOME="$LEARN_HOME" "$BIN" --learned-count

  # (4) Home renders a real PNG for an EMPTY WARBLE_HOME (no history.json at all — the first-run
  # look) and for a POPULATED one (every retention feature at once: the WPM/typist line, human
  # units, the streak heatmap, the merged recent+learned feed, the share-card button, per-app
  # bars). Dates are relative to "now" (like make_orphan's backdated WAV) so the populated state
  # stays genuinely populated (a real streak, a heatmap with lit cells) no matter when this runs.
  HOME_DIR="$REGTMP/home-renders"
  mkdir -p "$HOME_DIR"
  EMPTY_HOME="$REGTMP/retention-empty"
  mkdir -p "$EMPTY_HOME"
  EMPTY_PNG="$HOME_DIR/empty.png"
  if env WARBLE_HOME="$EMPTY_HOME" "$BIN" --render-home "$EMPTY_PNG" >/dev/null 2>&1 && [ -s "$EMPTY_PNG" ]; then
    EMPTY_W=$(sips -g pixelWidth "$EMPTY_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    EMPTY_H=$(sips -g pixelHeight "$EMPTY_PNG" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    if [ "$EMPTY_W" = "1480" ] && [ "${EMPTY_H:-0}" -ge 300 ]; then
      ok "Home's empty state renders (1480x$EMPTY_H PNG)"
    else
      bad "Home's empty state renders offscreen at 2x (dims: ${EMPTY_W:-none}x${EMPTY_H:-none})"
    fi
  else
    bad "Home's empty state renders a nonzero PNG"
  fi

  RET_HOME="$REGTMP/retention-populated"
  mkdir -p "$RET_HOME"
  RET_TODAY_TS=$(date +%s)
  RET_TODAY_DAY=$(date +%Y-%m-%d)
  RET_YDAY_DAY=$(date -v-1d +%Y-%m-%d)
  {
    printf '{"id":"ret1","ts":%s,"day":"%s","text":"ship the myela engine today","words":5,"durationMs":1800,"appBundleId":"com.tinyspeck.slackmacgap","appName":"Slack","engine":"parakeet","kind":"dictate","correctionsCleaned":1}\n' \
      "$((RET_TODAY_TS - 90000))" "$RET_YDAY_DAY"
    printf '{"id":"ret2","ts":%s,"day":"%s","text":"final report is ready for review","words":6,"durationMs":2000,"appBundleId":"com.apple.mail","appName":"Mail","engine":"parakeet","kind":"dictate","correctionsCleaned":0}\n' \
      "$RET_TODAY_TS" "$RET_TODAY_DAY"
  } > "$RET_HOME/history.json"
  printf '{"id":"retl1","ts":%s,"word":"Myela","from":"miele"}\n' "$RET_TODAY_TS" > "$RET_HOME/learned.json"

  POP_PNG="$HOME_DIR/populated.png"
  if env WARBLE_HOME="$RET_HOME" "$BIN" --render-home "$POP_PNG" >/dev/null 2>&1 && [ -s "$POP_PNG" ]; then
    POP_W=$(sips -g pixelWidth "$POP_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    POP_H=$(sips -g pixelHeight "$POP_PNG" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    if [ "$POP_W" = "1480" ] && [ "${POP_H:-0}" -ge 900 ]; then
      ok "Home's populated state renders every retention feature (1480x$POP_H PNG)"
    else
      bad "Home's populated state renders offscreen at 2x (dims: ${POP_W:-none}x${POP_H:-none})"
    fi
  else
    bad "Home's populated state renders a nonzero PNG"
  fi

  # (4b) The corrections-cleaned counter (the SPEC GAP a stored-but-invisible field would fail)
  # must actually change what Home renders: the SAME two dictations, once with a real
  # correctionsCleaned total and once with it zeroed out, must NOT render at the same height — a
  # counter that's only ever written to history.json and never read by any view would render
  # identically either way.
  CC_ZERO_HOME="$REGTMP/retention-cc-zero"
  mkdir -p "$CC_ZERO_HOME"
  {
    printf '{"id":"ret1","ts":%s,"day":"%s","text":"ship the myela engine today","words":5,"durationMs":1800,"appBundleId":"com.tinyspeck.slackmacgap","appName":"Slack","engine":"parakeet","kind":"dictate","correctionsCleaned":0}\n' \
      "$((RET_TODAY_TS - 90000))" "$RET_YDAY_DAY"
    printf '{"id":"ret2","ts":%s,"day":"%s","text":"final report is ready for review","words":6,"durationMs":2000,"appBundleId":"com.apple.mail","appName":"Mail","engine":"parakeet","kind":"dictate","correctionsCleaned":0}\n' \
      "$RET_TODAY_TS" "$RET_TODAY_DAY"
  } > "$CC_ZERO_HOME/history.json"
  printf '{"id":"retl1","ts":%s,"word":"Myela","from":"miele"}\n' "$RET_TODAY_TS" > "$CC_ZERO_HOME/learned.json"

  CC_ZERO_PNG="$HOME_DIR/cc-zero.png"
  if env WARBLE_HOME="$CC_ZERO_HOME" "$BIN" --render-home "$CC_ZERO_PNG" >/dev/null 2>&1 && [ -s "$CC_ZERO_PNG" ]; then
    CC_ZERO_H=$(sips -g pixelHeight "$CC_ZERO_PNG" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    if [ -n "${CC_ZERO_H:-}" ] && [ -n "${POP_H:-}" ] && [ "$POP_H" -gt "$CC_ZERO_H" ]; then
      ok "the corrections-cleaned counter actually renders on Home (populated ${POP_H}px > zeroed ${CC_ZERO_H}px)"
    else
      bad "the corrections-cleaned counter changes Home's render vs an all-zero fixture (populated: ${POP_H:-none}px, zeroed: ${CC_ZERO_H:-none}px)"
    fi
  else
    bad "Home renders a nonzero PNG for the all-zero corrections fixture"
  fi

  # (5) "Save a stats card": guarded when there's nothing to share yet, a real @2x PNG at the
  # card's own fixed size (960x600 -> 1920x1200 @2x) once there is.
  CARD_EMPTY="$HOME_DIR/card-empty.png"
  if env WARBLE_HOME="$EMPTY_HOME" "$BIN" --render-share-card "$CARD_EMPTY" >/dev/null 2>&1; then
    bad "the share card refuses to render with nothing to share"
  else
    ok "the share card refuses to render with nothing to share"
  fi

  CARD_PNG="$HOME_DIR/card.png"
  if env WARBLE_HOME="$RET_HOME" "$BIN" --render-share-card "$CARD_PNG" >/dev/null 2>&1 && [ -s "$CARD_PNG" ]; then
    CARD_W=$(sips -g pixelWidth "$CARD_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    CARD_H=$(sips -g pixelHeight "$CARD_PNG" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    if [ "$CARD_W" = "1920" ] && [ "$CARD_H" = "1200" ]; then
      ok "the share card renders at its fixed size (1920x1200 PNG)"
    else
      bad "the share card renders at its fixed size (dims: ${CARD_W:-none}x${CARD_H:-none})"
    fi
  else
    bad "the share card renders a nonzero PNG once there's something to share"
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
  GAL_WANT=$((GAL_STEPS + 7 + 4 + 10 + 2 + 3)) # steps + onboarding variants + setup states + pill states + history detail + retention pass (home empty/populated + share card)
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
