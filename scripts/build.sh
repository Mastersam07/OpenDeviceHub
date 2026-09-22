#!/bin/bash
# Builds the package the way the viewer needs to be built.
#
# SwiftPM's link records the deployment target as the SDK version, so a plain `swift build` stamps
# the binary as macOS 14 and AppKit then draws the toolbar with its pre macOS 26 appearance: no
# grouped background behind the actions and no hover highlight. Stamping the real SDK fixes it
# without moving the deployment target.
#
# Usage: scripts/build.sh [extra swift build arguments]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
minimum_version=14.0

exec swift build --package-path "${repo_root}/engine" \
  -Xlinker -platform_version -Xlinker macos \
  -Xlinker "${minimum_version}" -Xlinker "${sdk_version}" \
  "$@"
