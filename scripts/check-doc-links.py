#!/usr/bin/env python3
"""Check that local links in the repository's front-door documents resolve.

Usage:
    python3 scripts/check-doc-links.py             # READMEs and governance docs
    python3 scripts/check-doc-links.py --all-docs  # also every docs/**/*.md
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = pathlib.Path(__file__).resolve().parent.parent
FRONT_DOOR = [
    "README.md",
    "README_CN.md",
    "README_TW.md",
    "CHANGELOG.md",
    "docs/README.md",
    "docs/releases/README.md",
    ".github/CONTRIBUTING.md",
    ".github/SECURITY.md",
    ".github/CODE_OF_CONDUCT.md",
    ".github/pull_request_template.md",
]
LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
HTML = re.compile(r"""(?:href|src|srcset)\s*=\s*["']([^"']+)["']""", re.I)
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
FENCE = re.compile(r"^\s*(```|~~~)")


def target_path(raw: str) -> str | None:
    raw = raw.strip()
    if raw.startswith("<"):
        close = raw.find(">")
        if close < 0:
            return None
        raw = raw[1:close]
    else:
        raw = raw.split()[0] if raw else ""
    if not raw or raw.startswith("#") or raw.startswith("//"):
        return None
    if SCHEME.match(raw):
        return None
    split = urlsplit(raw)
    if split.netloc:
        return None
    return unquote(split.path) or None


def links(text: str):
    in_fence = False
    for number, line in enumerate(text.splitlines(), 1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for match in LINK.finditer(line):
            yield number, match.group(1)
        for match in HTML.finditer(line):
            yield number, match.group(1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all-docs", action="store_true", help="check every docs/**/*.md")
    args = parser.parse_args()

    files = [ROOT / name for name in FRONT_DOOR if (ROOT / name).exists()]
    if args.all_docs:
        files.extend(sorted((ROOT / "docs").rglob("*.md")))
    files = sorted(set(files))

    missing = []
    for path in files:
        for number, raw in links(path.read_text(encoding="utf-8")):
            target = target_path(raw)
            if target is None:
                continue
            if target.startswith("/"):
                resolved = (ROOT / target.lstrip("/")).resolve()
            else:
                resolved = (path.parent / target).resolve()
            try:
                resolved.relative_to(ROOT)
            except ValueError:
                missing.append((path, number, raw, "escapes the repository"))
                continue
            if not resolved.exists():
                missing.append((path, number, raw, "missing"))

    for path, number, raw, reason in missing:
        print(f"{path.relative_to(ROOT)}:{number}: {reason}: {raw}")
    if missing:
        print(f"\n{len(missing)} broken link(s)", file=sys.stderr)
        return 1
    print(f"checked {len(files)} file(s); no broken local links")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
