#!/bin/bash
# Dumps the Objective-C surface of the simulator private frameworks from the active Xcode into
# build/private-headers/, which is git ignored. Nothing here is copied into the repository.
set -euo pipefail

developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
app_root="$(cd "${developer_dir}/../.." && pwd)"
xcode_build="$(xcodebuild -version | awk '/^Build version/ { print $3 }')"
xcode_version="$(xcodebuild -version | awk '/^Xcode/ { print $2 }')"

out_dir="$(cd "$(dirname "$0")/.." && pwd)/build/private-headers"
mkdir -p "${out_dir}"

echo "Xcode ${xcode_version} (${xcode_build})"
echo "Developer dir: ${developer_dir}"
echo "Output: ${out_dir}"
echo

resolve_binary() {
  for candidate in "$@"; do
    if [ -f "${candidate}" ]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

dump_framework() {
  local name="$1"
  shift
  local binary
  if ! binary="$(resolve_binary "$@")"; then
    echo "${name}: not found. Searched:"
    printf '  %s\n' "$@"
    return 0
  fi

  local out="${out_dir}/${name}-${xcode_build}.txt"
  {
    echo "Framework: ${name}"
    echo "Binary:    ${binary}"
    echo "Xcode:     ${xcode_version} (${xcode_build})"
    echo "Dumped:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo
    echo "## Exported symbols (nm -gU, filtered)"
    nm -gU "${binary}" 2>/dev/null | grep -E 'OBJC_CLASS|_Indigo|_SimDevice' || echo "(none matched)"
    echo
    echo "## Objective-C metadata (otool -ov)"
    otool -ov "${binary}" 2>/dev/null || echo "(otool produced no output)"
  } > "${out}"

  if command -v class-dump >/dev/null 2>&1; then
    class-dump "${binary}" > "${out_dir}/${name}-${xcode_build}-class-dump.h" 2>/dev/null || true
    echo "${name}: wrote ${out} and ${name}-${xcode_build}-class-dump.h"
  elif command -v ipsw >/dev/null 2>&1; then
    ipsw class-dump "${binary}" > "${out_dir}/${name}-${xcode_build}-class-dump.h" 2>/dev/null || true
    echo "${name}: wrote ${out} and ${name}-${xcode_build}-class-dump.h"
  else
    echo "${name}: wrote ${out} (install class-dump or ipsw for readable headers)"
  fi
}

dump_framework "CoreSimulator" \
  "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator" \
  "${developer_dir}/Library/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"

dump_framework "SimulatorKit" \
  "${app_root}/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit" \
  "${developer_dir}/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
