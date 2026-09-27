#!/bin/bash
# Packages the signed, stapled app into a DMG for download.
#
# Built after the app is stapled, never before: the app inside carries its own ticket, so a copy
# dragged out of the DMG passes Gatekeeper on a machine that has never been online. The DMG then
# gets a ticket of its own so the download itself is not flagged.
#
# create-dmg lays out the window (background, arrow, icon positions) and the disk icon on a read
# and write image before converting it, so the signature below still comes last. One pinned
# version keeps a DMG made by hand laid out the same as the one the release workflow makes.
#
# Usage: scripts/package-dmg.sh [app]
set -euo pipefail

create_dmg_version="8.1.0"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-${repo_root}/build/OpenDeviceHub.app}"
[ -d "${app}" ] || { echo "No app at ${app}" >&2; exit 1; }

installed="$(create-dmg --version 2>/dev/null || true)"
if [ "${installed}" != "${create_dmg_version}" ]; then
  echo "Needs create-dmg ${create_dmg_version}, found ${installed:-none}." >&2
  echo "Install it with: npm install --global create-dmg@${create_dmg_version}" >&2
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${app}/Contents/Info.plist")"
dmg="${repo_root}/build/OpenDeviceHub-${version}.dmg"
staging="$(mktemp -d)"
cleanup() { rm -rf "${staging}"; }
trap cleanup EXIT INT TERM

# Its progress goes to standard error, so standard output stays the DMG's path alone.
create-dmg --overwrite --no-version-in-filename --no-code-sign \
  --dmg-title="OpenDeviceHub ${version}" "${app}" "${staging}" >&2
made="$(find "${staging}" -maxdepth 1 -name '*.dmg' -print -quit)"
[ -n "${made}" ] || { echo "create-dmg made no DMG" >&2; exit 1; }

rm -f "${dmg}"
mv "${made}" "${dmg}"

if [ -n "${ODH_SIGNING_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "${ODH_SIGNING_IDENTITY}" "${dmg}"
fi

echo "${dmg}"
