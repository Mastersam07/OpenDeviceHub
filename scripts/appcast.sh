#!/bin/bash
# Writes build/appcast.xml for one release.
#
# Last in the chain, and the order is what makes the signature mean anything. The EdDSA signature
# covers the exact bytes of the file people download, so it is taken after notarizing, stapling and
# packaging. Anything that rewrites the artifact afterwards, a re-zip or a second staple, leaves a
# signature that no longer matches, and Sparkle then refuses the update without telling anyone.
#
# The feed produced here is not published. It goes to the appcast repository only once the release
# assets exist at the URL the enclosure names, because a feed pointing at a download that is not
# there yet breaks updates for everyone who reads it in the meantime.
#
# Usage: scripts/appcast.sh [artifact]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${repo_root}/build/OpenDeviceHub.app"
[ -d "${app}" ] || { echo "No app at ${app}" >&2; exit 1; }

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${app}/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${app}/Contents/Info.plist")"
minimum_system="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "${app}/Contents/Info.plist")"
artifact="${1:-${repo_root}/build/OpenDeviceHub-${version}.dmg}"
[ -f "${artifact}" ] || { echo "No artifact at ${artifact}" >&2; exit 1; }

# The same refusal as the checksums: a signature over an unstapled artifact describes a file nobody
# will download, and the mismatch only shows up as an update that silently never installs.
if ! xcrun stapler validate "${artifact}" >/dev/null 2>&1; then
  echo "$(basename "${artifact}") is not stapled. The signature comes after notarization, never before." >&2
  exit 1
fi

sign_update="$(find "${repo_root}/engine/.build/artifacts" -path "*/bin/sign_update" -not -path "*old_dsa*" | head -1)"
[ -x "${sign_update}" ] || { echo "sign_update was not found. Run swift package resolve." >&2; exit 1; }

# The key lives in the login keychain on a developer's machine and arrives as a file in CI, where
# there is no keychain to hold it.
if [ -n "${ODH_SPARKLE_KEY_PATH:-}" ]; then
  signed="$("${sign_update}" -f "${ODH_SPARKLE_KEY_PATH}" "${artifact}")"
else
  signed="$("${sign_update}" "${artifact}")"
fi
signature="$(printf '%s' "${signed}" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')"
length="$(printf '%s' "${signed}" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[ -n "${signature}" ] && [ -n "${length}" ] || { echo "sign_update gave: ${signed}" >&2; exit 1; }

# Checked rather than trusted: the length in the feed is what Sparkle compares the download against.
actual_length="$(stat -f%z "${artifact}")"
[ "${length}" = "${actual_length}" ] || {
  echo "sign_update reported ${length} bytes but the file is ${actual_length}" >&2
  exit 1
}

# That version's own release, not a floating "latest": an enclosure has to keep pointing at the
# build it was signed for, whatever is released afterwards.
download_url="https://github.com/Mastersam07/OpenDeviceHub/releases/download/v${version}/$(basename "${artifact}")"

notes="$(python3 - "${repo_root}/CHANGELOG.md" "${version}" <<'PY'
import html, sys
path, version = sys.argv[1], sys.argv[2]
lines, collecting, body = open(path).read().splitlines(), False, []
for line in lines:
    if line.startswith("## "):
        if collecting:
            break
        collecting = line[3:].strip().lstrip("v") == version
        continue
    if collecting:
        body.append(line)
text = "\n".join(body).strip()
print(html.escape(text) if text else f"Release {version}.")
PY
)"

output="${repo_root}/build/appcast.xml"
cat > "${output}" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>OpenDeviceHub</title>
    <link>https://mastersam07.github.io/appcast/simviewer.xml</link>
    <description>Updates for OpenDeviceHub.</description>
    <language>en</language>
    <item>
      <title>${version}</title>
      <pubDate>$(date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>${build_number}</sparkle:version>
      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${minimum_system}</sparkle:minimumSystemVersion>
      <description><![CDATA[${notes}]]></description>
      <enclosure url="${download_url}"
                 sparkle:edSignature="${signature}"
                 length="${length}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

echo "Wrote ${output}"
echo "  version         ${version} (build ${build_number})"
echo "  minimum system  ${minimum_system}"
echo "  length          ${length} bytes, matches the file on disk"
echo "  url             ${download_url}"
echo
echo "Not published. The feed goes to the appcast repository only once that URL serves the file."
