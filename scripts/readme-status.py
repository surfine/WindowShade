#!/usr/bin/env python3
"""Keep the release status line in the three READMEs in sync with the appcast.

The shipped appcast is the source of truth: prototype/Info.plist may already
carry the next unreleased version, while the appcast only lists builds users
can actually download.

Usage:
    python3 scripts/readme-status.py           # rewrite the status blocks
    python3 scripts/readme-status.py --check   # exit 1 when a block is stale
"""

from __future__ import annotations

import argparse
import email.utils
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APPCAST = ROOT / "site" / "public" / "appcast.xml"
START = "<!-- status:start -->"
END = "<!-- status:end -->"
RELEASE_URL = "https://github.com/surfine/WindowShade/releases/tag/v{version}"

# README file -> (status prefix, release-notes label)
LABELS = {
    "README.md": ("Current release", "Release notes"),
    "README_CN.md": ("当前版本", "发布说明"),
    "README_TW.md": ("目前版本", "釋出說明"),
}


def first_item(text: str) -> tuple[str, str, str, str]:
    match = re.search(r"<item>(.*?)</item>", text, re.S)
    if match is None:
        raise SystemExit(f"no <item> in {APPCAST}")
    block = match.group(1)

    def tag(name: str) -> str:
        found = re.search(rf"<{re.escape(name)}>(.*?)</{re.escape(name)}>", block, re.S)
        if found is None:
            raise SystemExit(f"no <{name}> in the first appcast item")
        return found.group(1).strip()

    version = tag("sparkle:shortVersionString")
    build = tag("sparkle:version")
    published = email.utils.parsedate_to_datetime(tag("pubDate"))
    # The item's own <link> is the release page: a rebuilt version (1.0.21 build 20261110.01)
    # ships under its own tag (v1.0.21.1), which the version string alone cannot tell.
    link = re.search(r"<link>(.*?)</link>", block, re.S)
    url = link.group(1).strip() if link else RELEASE_URL.format(version=version)
    return version, build, published.date().isoformat(), url


def status_line(name: str, version: str, build: str, date: str, url: str) -> str:
    prefix, notes = LABELS[name]
    separator = ": " if name == "README.md" else "："
    return f"**{prefix}{separator}{version}** · build {build} · {date} · [{notes}]({url})"


def replace_block(path: pathlib.Path, line: str) -> tuple[bool, str]:
    text = path.read_text(encoding="utf-8")
    start = text.find(START)
    end = text.find(END)
    if start < 0 or end < 0 or end < start:
        raise SystemExit(f"{path.relative_to(ROOT)}: missing {START} / {END}")
    expected = f"{START}\n\n{line}\n\n{END}"
    actual = text[start : end + len(END)]
    if actual == expected:
        return False, text
    updated = text[:start] + expected + text[end + len(END) :]
    return True, updated


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="report drift without writing")
    args = parser.parse_args()

    version, build, date, url = first_item(APPCAST.read_text(encoding="utf-8"))
    stale = 0
    for name in LABELS:
        path = ROOT / name
        changed, updated = replace_block(path, status_line(name, version, build, date, url))
        if changed:
            stale += 1
            if args.check:
                print(f"{name}: status line is stale")
            else:
                path.write_text(updated, encoding="utf-8")
                print(f"{name}: updated")
        elif not args.check:
            print(f"{name}: unchanged")

    if args.check and stale:
        print(f"\n{stale} README(s) need scripts/readme-status.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
