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

# A fixture dictionary makes --apply/--pronounce deterministic on any machine (the env var
# outranks the user's real dictionary; see Lexicon.fileURL / Pronouncer.fileURL).
DICT=$(mktemp "${TMPDIR:-/tmp}/warble-regression-dict.XXXXXX")
trap 'rm -f "$DICT"' EXIT
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
