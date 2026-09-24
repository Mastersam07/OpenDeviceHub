#!/bin/bash
# Packages the signed, stapled app into a DMG for download.
#
# Built after the app is stapled, never before: the app inside carries its own ticket, so a copy
# dragged out of the DMG passes Gatekeeper on a machine that has never been online. The DMG then
# gets a ticket of its own so the download itself is not flagged.
#
# Usage: scripts/package-dmg.sh [app]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-${repo_root}/build/OpenDeviceHub.app}"
[ -d "${app}" ] || { echo "No app at ${app}" >&2; exit 1; }

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${app}/Contents/Info.plist")"
dmg="${repo_root}/build/OpenDeviceHub-${version}.dmg"
staging="$(mktemp -d)"
cleanup() { rm -rf "${staging}"; }
trap cleanup EXIT INT TERM

ditto "${app}" "${staging}/$(basename "${app}")"
ln -s /Applications "${staging}/Applications"

rm -f "${dmg}"
hdiutil create -quiet -volname "OpenDeviceHub ${version}" -srcfolder "${staging}" \
  -ov -format UDZO "${dmg}"

if [ -n "${ODH_SIGNING_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "${ODH_SIGNING_IDENTITY}" "${dmg}"
fi

echo "${dmg}"
