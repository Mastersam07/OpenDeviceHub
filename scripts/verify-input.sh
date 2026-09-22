#!/bin/bash
# Checks that input and rotation still reach the guest after an Xcode update, by tapping known
# coordinates and turning the device, then reading back what it actually received.
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

# Upside down is refused by Face ID iPhones, which is the phone's own behaviour rather than a
# fault: SpringBoard has never rotated to it there. iPads take all four, and so do the Home button
# iPhones, which the chrome identifies by listing a home button.
device_type="$(xcrun simctl list devices -j | python3 -c "
import json, sys
want = sys.argv[1]
for devices in json.load(sys.stdin)['devices'].values():
    for device in devices:
        if device['udid'] == want:
            print(device.get('deviceTypeIdentifier', '')); raise SystemExit
" "${udid}")"

if [[ "${device_type}" == *iPad* ]] || "${odhub}" doctor 2>/dev/null | grep -q "buttons:.*home"; then
  upside_down_expected="UPSIDEDOWN"
else
  upside_down_expected="refused"
fi

last_orientation() {
  grep '^ORIENTATION' "${events}" | tail -1 | awk '{ print $2 }'
}

check_orientation() {
  local sent="$1" want="$2" before
  before="$(last_orientation)"
  "${odhub}" rotate "${udid}" "${sent}" >/dev/null
  sleep 3
  local got
  got="$(last_orientation)"
  if [ "${want}" = "refused" ]; then
    if [ "${got}" = "UPSIDEDOWN" ]; then
      echo "  UNEXPECTED ${sent} was obeyed, which this device is not supposed to do"
      return 1
    fi
    echo "  ok      ${sent} refused, as a Face ID phone should"
    return 0
  fi
  if [ "${got}" = "${want}" ]; then
    echo "  ok      ${sent} reported as ${got}"
    return 0
  fi
  echo "  WRONG   ${sent} reported as ${got:-nothing}, wanted ${want} (was ${before:-nothing})"
  return 1
}

echo "Orientation (${device_type##*SimDeviceType.}):"
check_orientation landscapeLeft LANDSCAPELEFT || failures=$((failures + 1))
check_orientation landscapeRight LANDSCAPERIGHT || failures=$((failures + 1))
check_orientation portrait PORTRAIT || failures=$((failures + 1))
check_orientation portraitUpsideDown "${upside_down_expected}" || failures=$((failures + 1))
"${odhub}" rotate "${udid}" portrait >/dev/null 2>&1 || true

if [ "${failures}" -eq 0 ]; then
  echo "PASS: every tap arrived where it was sent, and the device turned as expected."
  exit 0
fi
echo "FAIL: ${failures} check(s) did not pass. Event log:"
cat "${events}" 2>/dev/null | tail -20
exit 1
