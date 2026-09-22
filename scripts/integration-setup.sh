#!/bin/bash
# Puts the test host on a simulator so the integration tests have a real app to look at. With no
# argument it does every booted device.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_id="io.opendevicehub.testhost"

udids=()
if [ "$#" -gt 0 ]; then
  udids=("$@")
else
  while read -r udid; do
    udids+=("${udid}")
  done < <(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-Fa-f-]\{36\}\)) (Booted).*/\1/p')
fi

if [ "${#udids[@]}" -eq 0 ]; then
  echo "No booted simulator to set up." >&2
  exit 1
fi

app="$("${repo_root}/scripts/build-test-host.sh")"

for udid in "${udids[@]}"; do
  xcrun simctl install "${udid}" "${app}"
  echo "installed ${bundle_id} on ${udid}"
done
