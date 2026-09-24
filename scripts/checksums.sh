#!/bin/bash
# Writes build/SHA256SUMS for the artifacts people download.
#
# Run last, after stapling. Stapling rewrites the artifact to put the ticket inside it, so a sum
# taken before that describes a file nobody will ever have. Each artifact is checked for a ticket
# first and the run fails if one is missing, because a published checksum that does not match the
# published file is worse than no checksum at all.
#
# Paths in the file are bare names, so `shasum -c SHA256SUMS` works from whatever directory the
# files were downloaded into.
#
# Usage: scripts/checksums.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build="${repo_root}/build"
output="${build}/SHA256SUMS"

artifacts=()
while IFS= read -r artifact; do
  artifacts+=("$(basename "${artifact}")")
done < <(find "${build}" -maxdepth 1 -name "*.dmg" | sort)

[ "${#artifacts[@]}" -gt 0 ] || { echo "No artifacts in ${build}" >&2; exit 1; }

for artifact in "${artifacts[@]}"; do
  if ! xcrun stapler validate "${build}/${artifact}" >/dev/null 2>&1; then
    echo "${artifact} is not stapled. Checksums come after notarization, never before." >&2
    exit 1
  fi
done

( cd "${build}" && shasum -a 256 "${artifacts[@]}" > "SHA256SUMS" )

echo "Wrote ${output}"
sed 's/^/  /' "${output}"
