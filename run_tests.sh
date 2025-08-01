#!/usr/bin/env bash
set -uo pipefail

mkdir -p test_results

fail_count=0

trap 'echo "Interrupted! Killing tests..."; pkill -P $$; exit 130' INT

grep -rH 'module mk[^ ]\+(Empty);' --include="*.bsv" . \
  | sed -nE 's|^(.+):.*module (mk[^ ]+)\(Empty\);|\1 \2|p' \
  | while read -r file module; do
    echo "==== Running test for $module from $file ===="
    stdout="test_results/${module}.out"
    stderr="test_results/${module}.err"

    timeout --foreground 240s bash -c "exec make b_all TOPFILE='$file' TOPMODULE='$module'" \
      > "$stdout" 2> "$stderr"
    status=$?

    if [ $status -eq 124 ]; then
      echo "❌ TIMEOUT: $module did not finish in 4 minutes."
      ((fail_count++))
    elif [ -s "$stderr" ]; then
      echo "❌ FAIL: $module encountered errors. See $stderr"
      ((fail_count++))
    else
      echo "✅ PASS: $module built successfully."
    fi
    echo ""
done

if [ $fail_count -ne 0 ]; then
  echo "$fail_count test(s) failed or timed out."
  exit 1
else
  echo "All tests passed successfully."
  exit 0
fi