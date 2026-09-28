#!/bin/bash
# Measures what a device window costs on this Mac and compares it with a baseline taken here
# before: CPU and drawing while nothing on screen changes, memory, click to frame latency and, on a
# foldable, how evenly a fold is drawn.
#
# Needs a booted iPhone and a booted iPhone Duo; a device that is not booted is not measured, and a
# baseline that measured it then fails the comparison. Keep the Mac otherwise quiet while it runs.
#
# A baseline only compares with a run on the same Mac model, macOS, Xcode, power mode and build
# configuration.
#
# Usage: scripts/performance-check.sh [--baseline FILE] [--record-baseline | --measure-only]
#   (default)          compare with the baseline and exit 1 on a regression
#   --record-baseline  measure and write the baseline, accepting what was measured
#   --measure-only     measure and report, comparing with nothing
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
baseline="${repo_root}/performance/baseline.json"
mode="compare"

while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) baseline="$2"; shift ;;
    --record-baseline) mode="record" ;;
    --measure-only) mode="measure" ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "${mode}" = "compare" ] && [ ! -f "${baseline}" ]; then
  echo "No baseline at ${baseline}. Record one with --record-baseline first." >&2
  exit 2
fi

output="${repo_root}/build/performance/$(date +%Y%m%d-%H%M%S)"
mkdir -p "${output}"

variables=(ODH_INTEGRATION=1 "ODH_PERFORMANCE_REPORT=${output}")
case "${mode}" in
  compare) variables+=("ODH_PERFORMANCE_BASELINE=${baseline}") ;;
  record) variables+=("ODH_PERFORMANCE_RECORD=${baseline}") ;;
esac

status=0
env "${variables[@]}" swift test --package-path "${repo_root}/engine" \
  -c release -Xswiftc -enable-testing --filter PerformanceCheckTests \
  > "${output}/test.log" 2>&1 || status=$?

if [ -f "${output}/performance.txt" ]; then
  cat "${output}/performance.txt"
else
  echo "The check produced no report. The test log is at ${output}/test.log." >&2
  grep -E "error:|skipped" "${output}/test.log" | head -10 >&2 || true
  exit 2
fi
echo "Results are in ${output}"
[ "${mode}" = "record" ] && [ "${status}" -eq 0 ] && echo "Recorded the baseline at ${baseline}"
exit $(( status == 0 ? 0 : 1 ))
