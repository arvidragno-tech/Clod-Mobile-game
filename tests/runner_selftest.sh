#!/usr/bin/env bash
# Proves the test runner's failure detection (tests/check_log.sh) works:
# a run that exits 0 and prints its pass marker must still FAIL when it logs
# a missing resource, a script error or an unlisted engine error, or when the
# marker is missing; and must PASS when its only errors are allowlisted.
# Usage: tests/runner_selftest.sh [path-to-godot]   (run by run_tests.sh)
set -uo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
# shellcheck source=tests/check_log.sh
source tests/check_log.sh
TMP="$(mktemp -d)"
fails=0

expect() {  # expect <pass|fail> <description> <suite> <log> <code> <marker>
  local want="$1" what="$2"
  shift 2
  check_log "$@" >"$TMP/out" 2>&1
  local got=$([ $? -eq 0 ] && echo pass || echo fail)
  if [ "$got" = "$want" ]; then
    echo "  ok   $what -> $got"
  else
    echo "  FAIL $what -> $got (wanted $want)"
    sed 's/^/       /' "$TMP/out"
    fails=$((fails + 1))
  fi
}

# Real Godot runs.
"$GODOT" --headless --path . res://tests/runner_selftest.tscn -- --case=clean >"$TMP/clean.log" 2>&1
expect pass "clean run" selftest "$TMP/clean.log" $? "SELFTEST PASSED"
"$GODOT" --headless --path . res://tests/runner_selftest.tscn -- --case=missing >"$TMP/missing.log" 2>&1
code=$?
if grep -q "SELFTEST PASSED" "$TMP/missing.log" && [ $code -eq 0 ]; then
  echo "  ok   the missing-resource run exits 0 with its marker (exit code and SCRIPT ERROR alone would pass it)"
else
  echo "  FAIL the missing-resource run should exit 0 with its marker (exit $code)"
  fails=$((fails + 1))
fi
expect fail "missing resource" selftest "$TMP/missing.log" $code "SELFTEST PASSED"

# The checker's other rules, on fixed log text.
printf 'ERROR: Condition "status < 0" is true. Returning: ERR_CANT_OPEN\n   at: init_output_device (drivers/alsa/audio_driver_alsa.cpp:90)\nDONE OK\n' >"$TMP/a.log"
expect pass "allowlisted error only" selftest "$TMP/a.log" 0 "DONE OK"
printf 'ERROR: Parse JSON failed. Error at line 0: Unexpected character.\nDONE OK\n' >"$TMP/b.log"
expect pass "save-fuzz error in its own suite" stability "$TMP/b.log" 0 "DONE OK"
expect fail "save-fuzz error in another suite" narrative "$TMP/b.log" 0 "DONE OK"
printf 'ERROR: pushed by script\n   at: push_error (core/variant/variant_utility.cpp:1092)\nDONE OK\n' >"$TMP/c.log"
expect fail "push_error" selftest "$TMP/c.log" 0 "DONE OK"
printf 'SCRIPT ERROR: Invalid call.\nDONE OK\n' >"$TMP/d.log"
expect fail "script error" selftest "$TMP/d.log" 0 "DONE OK"
printf 'nothing to see\n' >"$TMP/e.log"
expect fail "no pass marker" selftest "$TMP/e.log" 0 "DONE OK"
expect fail "non-zero exit" selftest "$TMP/a.log" 1 "DONE OK"

rm -rf "$TMP"
if [ $fails -eq 0 ]; then echo "RUNNER SELFTEST PASSED"; else echo "RUNNER SELFTEST FAILED ($fails)"; fi
exit $(( fails > 0 ))
