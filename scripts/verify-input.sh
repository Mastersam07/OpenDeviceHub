#!/bin/bash
# Checks that input still reaches the guest after an Xcode update, by tapping known coordinates and
# reading back what the device actually received.
#
# This reads the test host app's own event log rather than comparing screenshots. Screenshot
# comparison proved fragile: the clock changes every minute, and a crop that includes the status bar
# reports a change that never happened.
#
# Usage: scripts/verify-input.sh [udid]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_id="io.opendevicehub.testhost"
odhub="${repo_root}/engine/.build/debug/odhub"

udid="${1:-}"
if [ -z "${udid}" ]; then
  udid="$(xcrun simctl list devices booted -j | python3 -c "
import json, sys
for runtime, devices in json.load(sys.stdin)['devices'].items():
    for device in devices:
        print(device['udid']); raise SystemExit
raise SystemExit('no booted simulator, boot one first')")"
fi

[ -x "${odhub}" ] || swift build --package-path "${repo_root}/engine" >/dev/null
app="$("${repo_root}/scripts/build-test-host.sh")"

echo "Device: ${udid}"
echo "Xcode:  $(xcodebuild -version | tr '\n' ' ')"

xcrun simctl uninstall "${udid}" "${bundle_id}" >/dev/null 2>&1 || true
xcrun simctl install "${udid}" "${app}"
xcrun simctl launch "${udid}" "${bundle_id}" >/dev/null
sleep 4

container="$(xcrun simctl get_app_container "${udid}" "${bundle_id}" data)"
events="${container}/Documents/events.txt"

expected_taps=("0.5000 0.7000" "0.2500 0.3000" "0.8000 0.6000")
for point in "${expected_taps[@]}"; do
  read -r x y <<< "${point}"
  "${odhub}" tap "${udid}" --x "${x}" --y "${y}" >/dev/null
  sleep 1
done
sleep 1

failures=0
for point in "${expected_taps[@]}"; do
  read -r x y <<< "${point}"
  if python3 - "${events}" "${x}" "${y}" <<'PY'
import sys
path, want_x, want_y = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
found = False
for line in open(path):
    parts = line.split()
    if len(parts) == 3 and parts[0] == "TAP":
        if abs(float(parts[1]) - want_x) < 0.01 and abs(float(parts[2]) - want_y) < 0.01:
            found = True
raise SystemExit(0 if found else 1)
PY
  then
    echo "  ok      tap at ${x}, ${y} arrived"
  else
    echo "  MISSING tap at ${x}, ${y}"
    failures=$((failures + 1))
  fi
done

if [ "${failures}" -eq 0 ]; then
  echo "PASS: every tap reached the device at the coordinates it was sent to."
  exit 0
fi
echo "FAIL: ${failures} tap(s) did not arrive. Event log:"
cat "${events}" 2>/dev/null | tail -20
exit 1
