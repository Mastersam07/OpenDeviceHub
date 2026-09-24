#!/bin/bash
# Builds build/OpenDeviceHub.app: the viewer, the odhub CLI beside it, an Info.plist and an icon.
#
# The bundle is what gives the app its name. Run as a bare executable it is called odhub-viewer,
# because that is all macOS has to go on; inside a bundle the name comes from CFBundleName.
#
# Usage: scripts/build-app.sh [debug|release]
#
# A release build takes its marketing version from the VERSION file and its build number from
# ODH_BUILD_NUMBER, or the commit count when that is unset. A debug build is marked as a development
# build and never carries a release version, so an unreleased copy cannot pretend to be one.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
case "${configuration}" in
  debug|release) ;;
  *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac

app="${repo_root}/build/OpenDeviceHub.app"
contents="${app}/Contents"

if [ "${configuration}" = "release" ]; then
  marketing_version="$(tr -d '[:space:]' < "${repo_root}/VERSION")"
  build_number="${ODH_BUILD_NUMBER:-$(git -C "${repo_root}" rev-list --count HEAD)}"
else
  marketing_version="0.0.0-dev"
  build_number="0"
fi

# arm64 only, on purpose. The simulator frameworks this app dlopens from Xcode are arm64e with no
# Intel slice, so an x86_64 build would launch and then fail at the first framework load. Set
# ODH_ARCHS to build otherwise.
architectures=()
for architecture in ${ODH_ARCHS:-arm64}; do
  architectures+=(--arch "${architecture}")
done

echo "Building ${configuration} ${marketing_version} (${build_number}) for ${ODH_ARCHS:-arm64}"
# One product per invocation: swift build takes a single --product and quietly builds nothing
# useful when given two.
for product in odhub-viewer odhub; do
  "${repo_root}/scripts/build.sh" --configuration "${configuration}" "${architectures[@]}" \
    --product "${product}" >/dev/null
done
binaries="$("${repo_root}/scripts/build.sh" --configuration "${configuration}" \
  "${architectures[@]}" --show-bin-path)"

rm -rf "${app}"
mkdir -p "${contents}/MacOS" "${contents}/Resources" "${contents}/Frameworks"

# The viewer is installed under the app's own name so the process is called OpenDeviceHub
# everywhere, including Activity Monitor. The CLI keeps its name, because that is what is typed.
cp "${binaries}/odhub-viewer" "${contents}/MacOS/OpenDeviceHub"
cp "${binaries}/odhub" "${contents}/MacOS/odhub"

# Sparkle ships nested helpers of its own, an Autoupdate binary, an Updater.app and two XPC
# services, which is why it is copied with ditto rather than cp: the symlinks in a framework's
# Versions layout have to survive, and every one of those helpers has to be signed separately
# before the app is sealed.
sparkle="${binaries}/Sparkle.framework"
if [ ! -d "${sparkle}" ]; then
  sparkle="$(find "${repo_root}/engine/.build/artifacts" -name Sparkle.framework -type d | head -1)"
fi
[ -d "${sparkle}" ] || { echo "Sparkle.framework was not found" >&2; exit 1; }
ditto "${sparkle}" "${contents}/Frameworks/Sparkle.framework"

sed -e "s/__MARKETING_VERSION__/${marketing_version}/" \
    -e "s/__BUILD_NUMBER__/${build_number}/" \
    "${repo_root}/packaging/Info.plist" > "${contents}/Info.plist"

if [ "${configuration}" != "release" ]; then
  # A build from source has no business on the release channel. Without these two keys the updater
  # is never created, so a development copy cannot be offered the released version as an "update".
  /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "${contents}/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "${contents}/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "${contents}/Info.plist" >/dev/null 2>&1 || true
fi

iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${iconset}"
xcrun swiftc -O -o "${iconset}/../make-icon" "${repo_root}/packaging/make-icon.swift" >/dev/null
"${iconset}/../make-icon" "${iconset}" >/dev/null
iconutil --convert icns "${iconset}" --output "${contents}/Resources/AppIcon.icns"

printf 'APPL????' > "${contents}/PkgInfo"

echo "Built ${app}"
lipo -info "${contents}/MacOS/OpenDeviceHub" | sed 's/^/  /'
lipo -info "${contents}/MacOS/odhub" | sed 's/^/  /'
echo "  Sparkle: $(ls "${contents}/Frameworks")"
echo "  nested helpers to sign first:"
find "${contents}/Frameworks/Sparkle.framework/Versions/B" -maxdepth 2 \
  \( -name Autoupdate -o -name "Updater.app" -o -name "*.xpc" \) | sed "s|${contents}/Frameworks/|    |"
