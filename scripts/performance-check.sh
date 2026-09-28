#!/bin/bash
# Measures what a device window costs on this Mac and compares it with a baseline taken here
# before: how long it takes to open, CPU, energy, GPU and drawing while nothing on screen changes,
# memory, click to frame latency and, on a foldable, how evenly a fold is drawn. Then every booted
# device's window is opened at once, measured the same way and kept busy with clicks and folds to
# see whether memory keeps growing.
#
# Needs a booted iPhone and a booted iPhone Duo; a device that is not booted is not measured, and a
# baseline that measured it then fails the comparison. Every other booted device joins the windows
# opened at once. Keep the Mac otherwise quiet while it runs.
#
# A baseline only compares with a run on the same Mac model, macOS, Xcode, power mode, build
# configuration, booted devices and busy time. Low Power Mode caps drawing at 60 a second, so there
# is one baseline for each: performance/baseline-low-power.json and
# performance/baseline-normal-power.json, and the one that matches the Mac right now is used unless
# --baseline names another.
#
# Usage: scripts/performance-check.sh [--baseline FILE] [--busy-minutes N]
#                                     [--record-baseline | --measure-only]
#   (default)          compare with the baseline and exit 1 on a regression
#   --busy-minutes N   how long to keep the windows busy, 3 unless given
#   --record-baseline  measure and write the baseline, accepting what was measured
#   --measure-only     measure and report, comparing with nothing
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$(pmset -g | awk '/lowpowermode/ {print $2}')" = "1" ]; then
  baseline="${repo_root}/performance/baseline-low-power.json"
else
  baseline="${repo_root}/performance/baseline-normal-power.json"
fi
mode="compare"
busy_minutes=3

while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) baseline="$2"; shift ;;
    --busy-minutes) busy_minutes="$2"; shift ;;
    --record-baseline) mode="record" ;;
    --measure-only) mode="measure" ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

if ! [[ "${busy_minutes}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "--busy-minutes takes a number of minutes, not ${busy_minutes}" >&2
  exit 2
fi
busy_seconds="$(awk -v minutes="${busy_minutes}" 'BEGIN { printf "%d", minutes * 60 }')"

if [ "${mode}" = "compare" ] && [ ! -f "${baseline}" ]; then
  echo "No baseline at ${baseline}. Record one with --record-baseline first." >&2
  exit 2
fi

output="${repo_root}/build/performance/$(date +%Y%m%d-%H%M%S)"
mkdir -p "${output}"

variables=(ODH_INTEGRATION=1 "ODH_PERFORMANCE_REPORT=${output}" "ODH_PERFORMANCE_BUSY_SECONDS=${busy_seconds}")
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
