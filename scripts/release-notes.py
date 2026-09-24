#!/usr/bin/env python3
"""Prints the body of a GitHub Release.

The changes come from CHANGELOG.md, so the release page and the notes inside the update feed cannot
drift apart. What follows them is the same for every release: what you need, where the gaps are
written down, how to check the download, who to credit and where to say something.

The limitations come from the README rather than being repeated here, so a gap that gets fixed
disappears from both at once.

Usage: scripts/release-notes.py <version>
"""
import pathlib
import sys

import importlib.util

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPOSITORY = "https://github.com/Mastersam07/OpenDeviceHub"


def changelog_section(version: str) -> str:
    spec = importlib.util.spec_from_file_location(
        "changelog_section", ROOT / "scripts" / "changelog-section.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.section((ROOT / "CHANGELOG.md").read_text(), version)


def readme_section(heading: str) -> str:
    collecting = False
    body: list[str] = []
    for line in (ROOT / "README.md").read_text().splitlines():
        if line.startswith("## "):
            if collecting:
                break
            collecting = line[3:].strip() == heading
            continue
        if collecting:
            body.append(line)
    return "\n".join(body).strip()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    version = sys.argv[1]

    changes = changelog_section(version)
    if not changes:
        print(f"No '## {version}' section in CHANGELOG.md", file=sys.stderr)
        return 1

    requirements = readme_section("Requirements")
    limitations = readme_section("Current limitations")
    if not requirements or not limitations:
        print("README.md is missing Requirements or Current limitations", file=sys.stderr)
        return 1
    # The README's closing invitation belongs on its own page, not in release notes.
    limitations = limitations.split("Want to help close one of these?")[0].strip()

    print(f"""{changes}

## Requirements

{requirements}

## Known gaps

This is a pre-release. These are the ones worth knowing before you install it:

{limitations}

## Verifying the download

The app is signed with a Developer ID certificate, notarized by Apple and stapled, so it launches
without a Gatekeeper warning. `SHA256SUMS` is attached; to check the DMG against it:

```sh
shasum -a 256 -c SHA256SUMS
```

## Credits

Built after studying two MIT licensed projects, and better for both:
[Siniulator](https://github.com/kmagiera/Siniulator) by Krzysztof Magiera, and
[idb / FBSimulatorControl](https://github.com/facebook/idb) by Meta. What was adapted from each, down
to the individual constants, is listed in
[THIRD_PARTY_NOTICES.md]({REPOSITORY}/blob/dev/THIRD_PARTY_NOTICES.md).

## Tell me what breaks

This is the first release and it has been used by one person on one Mac. If something does not work,
please [open an issue]({REPOSITORY}/issues/new/choose): `odhub doctor` prints almost
everything the bug form asks for.""")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
