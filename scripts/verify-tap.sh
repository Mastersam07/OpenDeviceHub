#!/bin/bash
# Checks that a tap still lands after an Xcode update, by tapping the Settings icon on the home
# screen and confirming Settings actually launched.
#
# The Indigo touch path is private and its wire format is verified by observation, not by any
# contract, so rerun this after every Xcode upgrade before trusting input.
#
# Usage: scripts/verify-tap.sh [udid] [x] [y]
# The default coordinates are the Settings icon on an iPhone 17 Pro home screen running iOS 26.5.
# On another device or a rearranged home screen, take a screenshot and pass your own ratios.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
binary="${repo_root}/engine/.build/debug/odhub"
device_name="iPhone 17 Pro"
bundle_id="com.apple.Preferences"

udid="${1:-}"
x="${2:-0.8447}"
y="${3:-0.4857}"

if [ -z "${udid}" ]; then
  udid="$(xcrun simctl list devices available -j \
    | python3 -c "import json,sys
data = json.load(sys.stdin)['devices']
for runtime, devices in data.items():
    for device in devices:
        if device['name'] == '${device_name}' and device.get('isAvailable'):
            print(device['udid']); raise SystemExit
raise SystemExit('no available ${device_name}')")"
fi

if [ ! -x "${binary}" ]; then
  echo "Building..."
  swift build --package-path "${repo_root}/engine" >/dev/null
fi

echo "Device:      ${udid}"
echo "Tap target:  ${x}, ${y}"
echo "Xcode:       $(xcodebuild -version | tr '\n' ' ')"

if ! xcrun simctl list devices booted | grep -q "${udid}"; then
  echo "Booting..."
  xcrun simctl boot "${udid}"
  xcrun simctl bootstatus "${udid}" -b >/dev/null
fi

# Any foreground app hides the home screen, so everything this script might have launched is
# closed first. A miss here shows up as "did not land" rather than as a flaky result.
running_apps() {
  xcrun simctl spawn "${udid}" launchctl list 2>/dev/null \
    | grep -o 'UIKitApplication:[a-zA-Z0-9._-]*' | sed 's/UIKitApplication://' || true
}
for app in $(running_apps); do
  case "${app}" in
    com.apple.springboard|com.apple.Spotlight|com.apple.chrono.*|com.apple.mobilecal) ;;
    *) xcrun simctl terminate "${udid}" "${app}" >/dev/null 2>&1 || true ;;
  esac
done
sleep 3

before="$(running_apps | grep -c "^${bundle_id}$" || true)"
if [ "${before}" != "0" ]; then
  echo "FAIL: ${bundle_id} was still running before the tap."
  exit 1
fi

"${binary}" tap "${udid}" --x "${x}" --y "${y}"
sleep 4
after="$(running_apps | grep -c "^${bundle_id}$" || true)"

screenshot="${repo_root}/build/verify-tap.png"
mkdir -p "$(dirname "${screenshot}")"
xcrun simctl io "${udid}" screenshot "${screenshot}" >/dev/null 2>&1 || true

if [ "${after}" -gt 0 ]; then
  echo "PASS: the tap launched ${bundle_id}."
  echo "Screenshot: ${screenshot}"
  exit 0
fi

echo "FAIL: ${bundle_id} did not launch, so the tap did not land."
echo "Check ${screenshot}: if the home screen is not showing, or the icon has moved,"
echo "pass the correct ratios as arguments rather than treating this as a regression."
exit 1
