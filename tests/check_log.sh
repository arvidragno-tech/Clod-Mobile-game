#!/usr/bin/env bash
# Shared by tests/run_tests.sh and tests/runner_selftest.sh.
#
# check_log <suite-id> <log-file> <exit-code> <pass-marker-regex>
# Fails (returns 1, prints why) when:
#   - the exit code is not 0,
#   - the log has a "SCRIPT ERROR",
#   - the log has an "ERROR:" line that tests/expected_errors.txt doesn't
#     allow for this suite (missing resources, push_error, engine errors),
#   - the suite's pass marker is missing (it stopped early or said nothing).

CHECK_LOG_ALLOWLIST="${CHECK_LOG_ALLOWLIST:-$(dirname "${BASH_SOURCE[0]}")/expected_errors.txt}"

# Prints the allowlist regexes that apply to a suite, one per line.
allowed_patterns() {
  local suite="$1"
  awk -v s="$suite" '
    /^[[:space:]]*(#|$)/ { next }
    {
      scope = $1
      re = $0
      sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "", re)
      if (scope == "*" || scope == s) print re
    }' "$CHECK_LOG_ALLOWLIST"
}

check_log() {
  local suite="$1" log="$2" code="$3" marker="$4"
  local ok=0
  if [ "$code" -ne 0 ]; then
    echo "    -> FAILED: exit code $code"
    ok=1
  fi
  if grep -q "SCRIPT ERROR" "$log"; then
    echo "    -> FAILED: script error"
    grep -A2 "SCRIPT ERROR" "$log" | head -12 | sed 's/^/       /'
    ok=1
  fi
  local patterns unexpected
  patterns="$(allowed_patterns "$suite")"
  if [ -n "$patterns" ]; then
    unexpected="$(grep -E '^ERROR:' "$log" | grep -E -v -f <(printf '%s\n' "$patterns"))"
  else
    unexpected="$(grep -E '^ERROR:' "$log")"
  fi
  if [ -n "$unexpected" ]; then
    echo "    -> FAILED: unexpected engine errors (see tests/expected_errors.txt)"
    printf '%s\n' "$unexpected" | sort | uniq -c | head -12 | sed 's/^/       /'
    ok=1
  fi
  if ! grep -Eq "$marker" "$log"; then
    echo "    -> FAILED: no pass marker (/$marker/) in the output"
    ok=1
  fi
  return $ok
}
