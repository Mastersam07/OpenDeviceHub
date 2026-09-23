#!/usr/bin/env python3
"""Prints one version's section of CHANGELOG.md.

The release notes on GitHub and the notes inside the update feed come from the same place, so the
two cannot drift apart.

Usage: scripts/changelog-section.py <version>
"""
import pathlib
import sys


def section(text: str, version: str) -> str:
    collecting = False
    body: list[str] = []
    for line in text.splitlines():
        if line.startswith("## "):
            if collecting:
                break
            collecting = line[3:].strip().lstrip("v") == version
            continue
        if collecting:
            body.append(line)
    return "\n".join(body).strip()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    version = sys.argv[1]
    changelog = pathlib.Path(__file__).resolve().parent.parent / "CHANGELOG.md"
    found = section(changelog.read_text(), version)
    if not found:
        print(f"No '## {version}' section in {changelog}", file=sys.stderr)
        return 1
    print(found)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
