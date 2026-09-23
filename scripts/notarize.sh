#!/bin/bash
# Notarizes one artifact and staples the ticket to it.
#
# Takes the App Store Connect key either as a path or as its contents, so the same script works from
# a checkout and from CI, where the key arrives in an environment variable and must never reach the
# filesystem unprotected. Either way it is written to a file created with restrictive permissions
# and removed on exit, including when the submission fails or the script is interrupted.
#
# The notarization log is fetched whether or not the submission was accepted. An accepted submission
# can still carry warnings, and they are the only warning anyone will get before the next one is a
# rejection.
#
# Usage: scripts/notarize.sh <artifact>
#   artifact: a .app, .dmg or .zip
# Environment:
#   ODH_ASC_KEY_ID, ODH_ASC_ISSUER_ID   required
#   ODH_ASC_KEY_PATH                    path to the .p8, or
#   ODH_ASC_KEY                         the contents of the .p8
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact="${1:-}"
[ -n "${artifact}" ] || { echo "Usage: $0 <artifact>" >&2; exit 1; }
[ -e "${artifact}" ] || { echo "No artifact at ${artifact}" >&2; exit 1; }

key_id="${ODH_ASC_KEY_ID:-}"
issuer="${ODH_ASC_ISSUER_ID:-}"
[ -n "${key_id}" ] && [ -n "${issuer}" ] || {
  echo "Set ODH_ASC_KEY_ID and ODH_ASC_ISSUER_ID." >&2
  exit 1
}

# Everything that must not outlive the script, removed by one trap so an early exit cannot leave a
# private key or an unencrypted archive behind.
workspace="$(mktemp -d)"
cleanup() {
  if [ -n "${workspace:-}" ] && [ -d "${workspace}" ]; then
    rm -rf "${workspace}"
  fi
}
trap cleanup EXIT INT TERM

key_file="${workspace}/asc.p8"
# Created empty with the permissions it needs before anything is written into it, so the contents
# are never briefly readable by anyone else.
(umask 077 && : > "${key_file}")
if [ -n "${ODH_ASC_KEY:-}" ]; then
  printf '%s' "${ODH_ASC_KEY}" > "${key_file}"
elif [ -n "${ODH_ASC_KEY_PATH:-}" ]; then
  [ -f "${ODH_ASC_KEY_PATH}" ] || { echo "No key at ${ODH_ASC_KEY_PATH}" >&2; exit 1; }
  cat "${ODH_ASC_KEY_PATH}" > "${key_file}"
else
  echo "Set ODH_ASC_KEY_PATH or ODH_ASC_KEY." >&2
  exit 1
fi

# Notarization takes an archive, not a bundle. A .app is zipped for submission and the ticket is
# stapled to the bundle afterwards, never to the zip, which is thrown away.
case "${artifact}" in
  *.app)
    submission="${workspace}/$(basename "${artifact}" .app).zip"
    ditto -c -k --keepParent "${artifact}" "${submission}"
    ;;
  *)
    submission="${artifact}"
    ;;
esac

logs="${repo_root}/build/notarization"
mkdir -p "${logs}"
name="$(basename "${artifact}")"

echo "Submitting ${name}"
set +e
xcrun notarytool submit "${submission}" \
  --key "${key_file}" --key-id "${key_id}" --issuer "${issuer}" \
  --wait --output-format json > "${logs}/${name}.submit.json"
status=$?
set -e
cat "${logs}/${name}.submit.json"

submission_id="$(python3 -c "
import json, sys
print(json.load(open('${logs}/${name}.submit.json')).get('id', ''))
" 2>/dev/null || true)"

if [ -n "${submission_id}" ]; then
  # Fetched whether accepted or not: an accepted submission can still carry warnings, and they are
  # the only notice before one of them becomes a rejection.
  xcrun notarytool log "${submission_id}" \
    --key "${key_file}" --key-id "${key_id}" --issuer "${issuer}" \
    > "${logs}/${name}.log.json" 2>/dev/null || true
  echo "Log: ${logs}/${name}.log.json"
  python3 - "${logs}/${name}.log.json" <<'PY' || true
import json, sys
try:
    log = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit
issues = log.get("issues") or []
print(f"  status: {log.get('status')}  issues: {len(issues)}")
for issue in issues[:20]:
    print(f"    {issue.get('severity')}: {issue.get('message')}  [{issue.get('path')}]")
PY
fi

[ "${status}" -eq 0 ] || { echo "Submission failed." >&2; exit "${status}"; }

echo "Stapling ${name}"
xcrun stapler staple "${artifact}"
xcrun stapler validate "${artifact}"
