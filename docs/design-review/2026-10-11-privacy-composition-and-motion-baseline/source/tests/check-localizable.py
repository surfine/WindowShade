#!/usr/bin/env python3
"""本地化键检查（R19）：缺键、缺译文、中文源句对不上、孤儿键都让构建失败。

用法：python3 tests/check-localizable.py [--repo DIR]

检查：
  1. Localizable.xcstrings 里每个键都有 zh-Hans 和 en，非空，占位符 %@ 个数一致。
  2. prototype/ 下每个 WSL10n.text("键", zh: …) 的键都在表里；zh 是不带插值的字面量时，必须和表里的 zh-Hans 逐字相同。
  3. WS2SilentCopy 里每条 id 都有 "silent.<id>"，中文逐字相同。
  4. 表里没有谁也不引用的键。
"""
import argparse
import json
import os
import re
import sys

CALL_RE = re.compile(r'WSL10n\.text\(\s*"([^"\\]+)"\s*,\s*zh:\s*("(?:[^"\\\n]|\\.)*")?')
SILENT_RE = re.compile(r'^\s*"([A-Za-z0-9_.]+)":\s*"((?:[^"\\\n]|\\.)*)"', re.M)


def swift_files(root):
    for base, dirs, files in os.walk(os.path.join(root, "prototype")):
        dirs[:] = [d for d in dirs if d not in (".build", "Vendor", "dist", "WindowShade.app", "Watchdog")]
        for name in files:
            if name.endswith(".swift"):
                yield os.path.join(base, name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    root = os.path.abspath(parser.parse_args().repo)
    failures = []
    table_path = os.path.join(root, "prototype", "Resources", "Localizable.xcstrings")
    strings = json.load(open(table_path, encoding="utf-8"))["strings"]

    zh = {}
    for key, entry in strings.items():
        loc = entry.get("localizations", {})
        values = {}
        for lang in ("zh-Hans", "en"):
            value = loc.get(lang, {}).get("stringUnit", {}).get("value", "")
            if not value:
                failures.append(f"{key}: 缺 {lang} 译文")
            values[lang] = value
        if values["zh-Hans"].count("%@") != values["en"].count("%@"):
            failures.append(f"{key}: zh-Hans 和 en 的 %@ 个数不同")
        zh[key] = values["zh-Hans"]

    used = set()
    for path in swift_files(root):
        text = open(path, encoding="utf-8").read()
        rel = os.path.relpath(path, root)
        for match in CALL_RE.finditer(text):
            key, literal = match.group(1), match.group(2)
            used.add(key)
            if key not in strings:
                failures.append(f"{rel}: 键 {key} 不在 Localizable.xcstrings")
                continue
            if literal and "\\(" not in literal:
                source = json.loads(literal)
                if source != zh[key]:
                    failures.append(f"{rel}: 键 {key} 的中文源句 {source!r} 和表里 {zh[key]!r} 不同")

    silent = open(os.path.join(root, "prototype", "Core", "WS2SilentCopy.swift"), encoding="utf-8").read()
    for ident, source in SILENT_RE.findall(silent):
        key = "silent." + ident
        used.add(key)
        if key not in strings:
            failures.append(f"WS2SilentCopy: 缺键 {key}")
        elif json.loads('"%s"' % source) != zh[key]:
            failures.append(f"WS2SilentCopy: {key} 的中文和表里不同")

    for key in strings:
        if key not in used:
            failures.append(f"{key}: 表里有，代码里没人用")

    if failures:
        print("本地化检查失败：")
        for line in failures:
            print("  - " + line)
        return 1
    print(f"本地化检查通过：{len(strings)} 个键，中英文齐全，中文源句和代码一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
