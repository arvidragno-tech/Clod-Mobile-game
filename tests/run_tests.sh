#!/usr/bin/env bash
# Full test pass: the runner's self-test, compile check, balance simulation,
# stability suite, the unit + end-to-end bot (mouse + keyboard) on the
# 1920x1080 canvas, and, when xvfb-run is installed, the rendered probes:
# display (real window at 1920x1080, 1600x900, 1366x768, 1280x720,
# borderless, fullscreen and a 5:4 letterbox), living world, city, UI,
# UI stability, UX, onboarding, 3.10 and narrative.
#
# A suite fails on a non-zero exit, a "SCRIPT ERROR", an engine "ERROR:" line
# that tests/expected_errors.txt doesn't allow for it (a missing resource,
# push_error...), or a missing pass marker (tests/check_log.sh).
# Without xvfb-run the rendered suites are SKIPPED and the run ends with
# "NOT ALL SUITES RAN" and exit code 2, never "ALL SUITES PASSED".
# Usage: tests/run_tests.sh [path-to-godot]   (default: godot on PATH)
set -uo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
# shellcheck source=tests/check_log.sh
source tests/check_log.sh
# A fresh clone needs one import pass before scripts can run.
[ -d .godot ] || "$GODOT" --headless --path . --import >/dev/null 2>&1
status=0
skipped=()
LOG="$(mktemp)"

# run_step <title> <suite-id> <summary-grep> <pass-marker> <command...>
run_step() {
  local title="$1" suite="$2" pattern="$3" marker="$4"
  shift 4
  echo "=== $title ==="
  "$@" >"$LOG" 2>&1
  local code=$?
  grep -E "$pattern|SCRIPT ERROR" "$LOG"
  check_log "$suite" "$LOG" "$code" "$marker" || status=1
}

# run_rendered <title> <suite-id> <pass-marker> <godot args...>
run_rendered() {
  local title="$1" suite="$2" marker="$3"
  shift 3
  if [ "$HAVE_XVFB" -eq 1 ]; then
    run_step "$title" "$suite" "FAIL|PASSED" "$marker" \
      xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --rendering-driver opengl3 "$@"
  else
    echo "=== $title: SKIPPED (no xvfb-run) ==="
    skipped+=("$suite")
  fi
}

HAVE_XVFB=0
command -v xvfb-run >/dev/null 2>&1 && HAVE_XVFB=1

echo "=== runner self-test (a missing resource must fail a suite) ==="
if ! out="$(tests/runner_selftest.sh "$GODOT" 2>&1)"; then
  status=1
  printf '%s\n' "$out"
  echo "    -> FAILED: the runner can't be trusted; fix tests/check_log.sh first"
else
  printf '%s\n' "$out" | grep -E "PASSED"
fi

run_step "compile check" compile "compile check|FAILED" "compile check: [0-9]+ files, 0 failed" \
  "$GODOT" --headless --path . res://tests/compile_check.tscn
for args in "--seed=1" "--seed=2" "--seed=3" "--seed=4 --skill=-0.3"; do
  # shellcheck disable=SC2086
  run_step "balance simulation $args" balance "BALANCE|FAIL" "BALANCE OK" \
    "$GODOT" --headless --path . res://tests/balance_sim.tscn -- --ops=40 $args
done
run_step "economy simulation (5 strategies x 3 seeds x 20 days, real systems)" economy "ECONOMY|MISS|== [A-Z]" "ECONOMY OK" \
  "$GODOT" --headless --path . res://tests/economy_sim.tscn -- --days=20 --seeds=3 --check
run_step "job offers (2000 per stage x 4 stages, real generator)" offers "OFFERS|MISS|== OFFER" "OFFERS OK" \
  "$GODOT" --headless --path . res://tests/offer_sim.tscn -- --offers=2000 --check
run_step "stability (soak, monkey, save fuzz, leaks)" stability "STABILITY|FAIL|completed|visited" "STABILITY OK" \
  "$GODOT" --headless --path . res://tests/stability_test.tscn -- --shifts=20 --monkey=1500
# The E2E bot needs real font metrics (headless Godot measures text taller
# than the renderer does), so it runs rendered under Xvfb when available.
E2E_SUMMARY="^  FAIL|run [0-9] grade|PASSED|FAILURES|^  - "
if [ "$HAVE_XVFB" -eq 1 ]; then
  run_step "unit + end-to-end (mouse + keyboard) at 1920x1080, rendered" e2e "$E2E_SUMMARY" "ALL TESTS PASSED" \
    xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1920x1080 \
    res://tests/test_runner.tscn -- --viewport=1920x1080
else
  run_step "unit + end-to-end (headless: layout checks approximate)" e2e "$E2E_SUMMARY" "ALL TESTS PASSED" \
    "$GODOT" --headless --path . res://tests/test_runner.tscn -- --viewport=1920x1080
  skipped+=("e2e-rendered")
fi
run_rendered "display probe (window sizes and modes)" display "DISPLAY PROBE PASSED" \
  res://tests/display_probe.tscn
run_rendered "living world probe (new screens at 1920x1080, 1600x900, 1366x768, 1280x720)" living "LIVING PROBE PASSED" \
  --resolution 1920x1080 res://tests/living_probe.tscn
run_rendered "living city probe (map, travel, places; 4 resolutions, 3 window modes; mouse + keyboard)" city "CITY PROBE PASSED" \
  --resolution 1920x1080 res://tests/city_probe.tscn
run_rendered "UI probe (field guide, explanations, at a glance, diagnosis; 4 resolutions, 3 window modes)" ui "UI PROBE PASSED" \
  --resolution 1920x1080 res://tests/ui_probe.tscn
run_rendered "UI stability probe (shop accuracy, double clicks, navigation, rapid switching, big text; 4 resolutions, 3 window modes)" ui_stability "UI STABILITY PROBE PASSED" \
  --resolution 1920x1080 res://tests/ui_stability_probe.tscn
run_rendered "UX probe (early game: controls, priorities, preview, follow, journal, changes; 4 resolutions, 3 window modes)" ux "UX PROBE PASSED" \
  --resolution 1920x1080 res://tests/ux_probe.tscn
run_rendered "onboarding probe (new player: sections by stage, patient summary, dashboard, previews, field guide; 4 resolutions, 3 window modes)" onboarding "ONBOARDING PROBE PASSED" \
  --resolution 1920x1080 res://tests/onboarding_probe.tscn
run_rendered "3.10 probe (scan finding explained, plan FOUND row, selling from storage)" clinic_310 "3.10 PROBE PASSED" \
  --resolution 1920x1080 res://tests/clinic_310_probe.tscn
run_rendered "3.11-3.12 narrative probe (opening scene, chapter card, skip, story case and decision, reactive case, breathers, seasons)" narrative "NARRATIVE PROBE PASSED" \
  --resolution 1920x1080 res://tests/narrative_probe.tscn
rm -f "$LOG"
if [ $status -ne 0 ]; then
  echo "SOME SUITES FAILED"
  exit 1
fi
if [ ${#skipped[@]} -gt 0 ]; then
  echo "NOT ALL SUITES RAN: ${#skipped[@]} skipped (${skipped[*]}); install xvfb-run for the rendered suites"
  exit 2
fi
echo "ALL SUITES PASSED"
exit 0
