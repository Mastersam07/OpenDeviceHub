#!/bin/bash
# Signs build/OpenDeviceHub.app with Developer ID and the hardened runtime.
#
# Inside out, deepest first. Code signing seals a bundle around what it contains, so signing the
# outer app first and a nested helper afterwards invalidates the outer seal. Notarization then
# rejects the whole thing, and the message points at the helper rather than at the ordering, which
# is why this is the usual cause of a failed first submission.
#
# `--deep` is never used to sign. It walks a bundle applying one set of options to everything it
# finds, which is not what nested helpers need and hides what was actually signed. It is used only
# to verify afterwards.
#
# Usage: ODH_SIGNING_IDENTITY="Developer ID Application: ..." scripts/sign-app.sh [app]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-${repo_root}/build/OpenDeviceHub.app}"
identity="${ODH_SIGNING_IDENTITY:-}"
entitlements="${ODH_ENTITLEMENTS:-}"

if [ -z "${identity}" ]; then
  echo "Set ODH_SIGNING_IDENTITY to a Developer ID Application identity." >&2
  echo "Available:" >&2
  security find-identity -v -p codesigning | grep "Developer ID Application" >&2 || true
  exit 1
fi
[ -d "${app}" ] || { echo "No app at ${app}" >&2; exit 1; }

sparkle="${app}/Contents/Frameworks/Sparkle.framework"
options=(--force --options runtime --timestamp --sign "${identity}")
if [ -n "${entitlements}" ]; then
  echo "Entitlements: ${entitlements}"
  options+=(--entitlements "${entitlements}")
else
  echo "Entitlements: none"
fi

sign() {
  echo "  signing ${1#"${app}/"}"
  codesign "${options[@]}" "$1"
}

echo "Signing ${app}"
echo "Identity: ${identity}"

# Deepest first. The XPC services sit inside Sparkle's versioned directory, so they are sealed
# before anything that contains them.
sign "${sparkle}/Versions/B/XPCServices/Downloader.xpc"
sign "${sparkle}/Versions/B/XPCServices/Installer.xpc"
sign "${sparkle}/Versions/B/Autoupdate"
sign "${sparkle}/Versions/B/Updater.app"
sign "${sparkle}/Versions/B"
# The command line tool is a separate Mach-O beside the app's own executable, so it carries its own
# signature rather than being covered by the app's.
sign "${app}/Contents/MacOS/odhub"
# Last, which seals everything above.
sign "${app}"

echo
echo "Verifying"
codesign --verify --deep --strict --verbose=2 "${app}" 2>&1 | sed 's/^/  /'
echo
echo "Spot checking each nested component on its own"
for component in \
  "${sparkle}/Versions/B/XPCServices/Downloader.xpc" \
  "${sparkle}/Versions/B/XPCServices/Installer.xpc" \
  "${sparkle}/Versions/B/Autoupdate" \
  "${sparkle}/Versions/B/Updater.app" \
  "${sparkle}" \
  "${app}/Contents/MacOS/odhub" \
  "${app}"; do
  printf '  %-56s ' "${component#"${app}/Contents/"}"
  if codesign --verify --strict "${component}" 2>/dev/null; then
    authority="$(codesign -dvv "${component}" 2>&1 | awk -F= '/^Authority=/ { print $2; exit }')"
    runtime="$(codesign -dv "${component}" 2>&1 | grep -c "runtime" || true)"
    printf 'ok   %s   hardened:%s\n' "${authority}" "$([ "${runtime}" != "0" ] && echo yes || echo no)"
  else
    printf 'FAILED\n'
    exit 1
  fi
done
