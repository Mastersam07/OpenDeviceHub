#!/bin/bash
# Builds the test host app the verification scripts install. It reports the orientation it is in
# and echoes taps, so a script can read the device's state from a screenshot.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="${repo_root}/testhost/ODHTestHost"
out_dir="${repo_root}/build/testhost"
bundle="${out_dir}/ODHTestHost.app"

sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
[ "${arch}" = "arm64" ] && target="arm64-apple-ios17.0-simulator" || target="x86_64-apple-ios17.0-simulator"

rm -rf "${bundle}"
mkdir -p "${bundle}"
xcrun swiftc -sdk "${sdk}" -target "${target}" \
  "${source_dir}/main.swift" -o "${bundle}/ODHTestHost"
cp "${source_dir}/Info.plist" "${bundle}/Info.plist"
echo "${bundle}"
