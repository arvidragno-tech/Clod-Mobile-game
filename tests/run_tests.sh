#!/usr/bin/env bash
# Full test pass: compile check, balance simulation, stability suite, and the
# unit + end-to-end bot at the two reference iPhone sizes (360x780, 360x640).
# Any failed check, non-zero exit or "SCRIPT ERROR" in the output fails the run.
# Usage: tests/run_tests.sh [path-to-godot]   (default: godot on PATH)
set -uo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
# A fresh clone needs one import pass before scripts can run.
[ -d .godot ] || "$GODOT" --headless --path . --import >/dev/null 2>&1
status=0
LOG="$(mktemp)"

# run_step <title> <summary-grep> <godot args...>
run_step() {
  local title="$1" pattern="$2"
  shift 2
  echo "=== $title ==="
  "$GODOT" --headless --path . "$@" >"$LOG" 2>&1
  local code=$?
  grep -E "$pattern|SCRIPT ERROR" "$LOG"
  if [ $code -ne 0 ] || grep -q "SCRIPT ERROR" "$LOG"; then
    status=1
    echo "    -> FAILED (exit $code)"
  fi
}

run_step "compile check" "compile check|FAILED" res://tests/compile_check.tscn
for args in "--seed=1" "--seed=2" "--seed=3" "--seed=4 --skill=-0.3"; do
  # shellcheck disable=SC2086
  run_step "balance simulation $args" "BALANCE|FAIL" res://tests/balance_sim.tscn -- --ops=40 $args
done
run_step "stability (soak, monkey, save fuzz, leaks)" "STABILITY|FAIL|completed|visited" \
  res://tests/stability_test.tscn -- --shifts=20 --monkey=1500
for vp in 360x780 360x640; do
  run_step "unit + end-to-end at $vp" "^  FAIL|run [0-9] grade|PASSED|FAILURES|^  - " \
    res://tests/test_runner.tscn -- --viewport="$vp"
done
# Notch / Dynamic Island + home indicator (iPhone 15-class insets).
run_step "unit + end-to-end at 360x780 with safe-area insets" "^  FAIL|PASSED|FAILURES|^  - " \
  res://tests/test_runner.tscn -- --viewport=360x780 --safe-area=54,31
rm -f "$LOG"
[ $status -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit $status
