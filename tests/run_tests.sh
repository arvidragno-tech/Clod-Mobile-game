#!/usr/bin/env bash
# Runs unit + end-to-end tests headless at the two reference iPhone sizes.
# Usage: tests/run_tests.sh [path-to-godot]   (default: godot on PATH)
set -uo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
# A fresh clone needs one import pass before scripts can run.
[ -d .godot ] || "$GODOT" --headless --path . --import >/dev/null 2>&1
status=0
echo "=== compile check ==="
"$GODOT" --headless --path . res://tests/compile_check.tscn 2>&1 | grep -E "compile check|FAILED|SCRIPT ERROR"
[ "${PIPESTATUS[0]}" -eq 0 ] || status=1
for vp in 360x780 360x640; do
  echo "=== viewport $vp ==="
  "$GODOT" --headless --path . res://tests/test_runner.tscn -- --viewport="$vp" 2>&1 \
    | grep -E "^  FAIL|run [0-9] grade|PASSED|FAILURES|^  - |SCRIPT ERROR"
  [ "${PIPESTATUS[0]}" -eq 0 ] || status=1
done
exit $status
