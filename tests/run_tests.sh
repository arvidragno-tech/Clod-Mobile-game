#!/usr/bin/env bash
# Full test pass: compile check, balance simulation, stability suite, the
# unit + end-to-end bot (mouse + keyboard) on the 1920x1080 canvas, and, when
# xvfb-run is installed, the display probe (real window at 1920x1080,
# 1600x900, 1366x768, 1280x720, borderless, fullscreen and a 5:4 letterbox).
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
# The E2E bot needs real font metrics (headless Godot measures text taller
# than the renderer does), so it runs rendered under Xvfb when available.
if command -v xvfb-run >/dev/null 2>&1; then
  echo "=== unit + end-to-end (mouse + keyboard) at 1920x1080, rendered ==="
  xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1920x1080 \
    res://tests/test_runner.tscn -- --viewport=1920x1080 >"$LOG" 2>&1
  code=$?
  grep -E "^  FAIL|run [0-9] grade|PASSED|FAILURES|^  - |SCRIPT ERROR" "$LOG"
  if [ $code -ne 0 ] || grep -q "SCRIPT ERROR" "$LOG"; then status=1; echo "    -> FAILED (exit $code)"; fi
else
  run_step "unit + end-to-end (headless: layout checks approximate)" "^  FAIL|run [0-9] grade|PASSED|FAILURES|^  - " \
    res://tests/test_runner.tscn -- --viewport=1920x1080
fi
if command -v xvfb-run >/dev/null 2>&1; then
  echo "=== display probe (window sizes and modes) ==="
  xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --rendering-driver opengl3 \
    res://tests/display_probe.tscn >"$LOG" 2>&1
  code=$?
  grep -E "FAIL|PASSED|SCRIPT ERROR" "$LOG"
  if [ $code -ne 0 ] || grep -q "SCRIPT ERROR" "$LOG"; then status=1; echo "    -> FAILED (exit $code)"; fi
else
  echo "=== display probe skipped (no xvfb-run) ==="
fi
rm -f "$LOG"
[ $status -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit $status
