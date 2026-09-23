#!/bin/bash
# Picks an Xcode and prints its developer directory and macOS SDK version.
#
# The linked SDK decides whether AppKit gives the app its current appearance or its pre macOS 26
# one, and an older SDK builds, signs and notarizes perfectly well while shipping a window that
# looks years out of date. So a release asks for a floor and the run stops if nothing meets it,
# rather than the mistake being found later in a screenshot.
#
# Usage: scripts/select-xcode.sh [preferred-major] [minimum-sdk]
#   preferred-major  tried first, for example 27. Falls back to the newest that meets the floor.
#   minimum-sdk      for example 26.0. Omitted or 0 means any.
#
# Prints two lines: DEVELOPER_DIR=... and MACOS_SDK=...
set -euo pipefail

preferred="${1:-}"
minimum="${2:-0}"

sdk_of() {
  DEVELOPER_DIR="$1/Contents/Developer" xcrun --sdk macosx --show-sdk-version 2>/dev/null || true
}

meets_floor() {
  local sdk="$1"
  [ -n "${sdk}" ] || return 1
  [ "${minimum}" = "0" ] && return 0
  [ "$(printf '%s\n%s\n' "${sdk}" "${minimum}" | sort -V | head -1)" = "${minimum}" ]
}

candidates=()
while IFS= read -r app; do
  candidates+=("${app}")
done < <(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V -r)

[ "${#candidates[@]}" -gt 0 ] || { echo "No Xcode in /Applications." >&2; exit 1; }

chosen=""
# The preferred major first, newest build of it, so a machine with several gets the latest.
if [ -n "${preferred}" ]; then
  for app in "${candidates[@]}"; do
    case "$(basename "${app}")" in
      "Xcode_${preferred}"*|"Xcode-${preferred}"*)
        if meets_floor "$(sdk_of "${app}")"; then chosen="${app}"; break; fi
        ;;
    esac
  done
fi

# Otherwise the newest that clears the floor, which is what keeps a release honest when the
# preferred version is not installed.
if [ -z "${chosen}" ]; then
  for app in "${candidates[@]}"; do
    if meets_floor "$(sdk_of "${app}")"; then chosen="${app}"; break; fi
  done
fi

if [ -z "${chosen}" ]; then
  echo "No Xcode with a macOS SDK of ${minimum} or newer. Found:" >&2
  for app in "${candidates[@]}"; do
    echo "  $(basename "${app}")  SDK $(sdk_of "${app}")" >&2
  done
  exit 1
fi

echo "DEVELOPER_DIR=${chosen}/Contents/Developer"
echo "MACOS_SDK=$(sdk_of "${chosen}")"
