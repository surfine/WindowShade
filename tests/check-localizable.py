#!/usr/bin/env python3
"""本地化键检查（R19）：缺键、缺译文、中文源句对不上、孤儿键都让构建失败。

用法：python3 tests/check-localizable.py [--repo DIR]

检查：
  1. Localizable.xcstrings 里每个键都有 zh-Hans 和 en，非空，占位符 %@ 个数一致；
     en 里不许出现汉字（漏译/把中文抄进英文列的防线；语言名这类不进表）。
  2. prototype/ 下每个 WSL10n.text("键", zh: …) 或 WSL10n.setting("键", zh: …) 的键都在表里；
     zh 是不带插值的字面量时，必须和表里的 zh-Hans 逐字相同。
  3. WS2SilentCopy 里每条 id 都有 "silent.<id>"，中文逐字相同。
  4. 表里没有谁也不引用的键。
"""
import argparse
import json
import os
import re
import sys

CALL_RE = re.compile(r'WSL10n\.(?:text|setting)\(\s*"([^"\\]+)"\s*,\s*zh:\s*("(?:[^"\\\n]|\\.)*")?')
SILENT_RE = re.compile(r'^\s*"([A-Za-z0-9_.]+)":\s*"((?:[^"\\\n]|\\.)*)"', re.M)
HAN_RE = re.compile(r'[\u4e00-\u9fff]')


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
        if HAN_RE.search(values["en"]):
            failures.append(f"{key}: en 译文里有汉字（漏译或抄了中文）")
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
    lines_match = re.search(r'static let lines: \[String: String\] = \[(.*?)\n    \]', silent, re.S)
    if not lines_match:
        failures.append("WS2SilentCopy: 找不到 lines 表")
        lines_body = silent
    else:
        lines_body = lines_match.group(1)
    for ident, source in SILENT_RE.findall(lines_body):
        key = "silent." + ident
        used.add(key)
        if key not in strings:
            failures.append(f"WS2SilentCopy: 缺键 {key}")
        elif json.loads('"%s"' % source) != zh[key]:
            failures.append(f"WS2SilentCopy: {key} 的中文和表里不同")

    # 状态散句表（第28批）：sayings 里的每条都要有 "say.<id>"，中文逐字相同。
    sayings_match = re.search(r'static let sayings: \[String: String\] = \[(.*?)\n    \]', silent, re.S)
    if not sayings_match:
        failures.append("WS2SilentCopy: 找不到 sayings 表")
    else:
        for ident, source in SILENT_RE.findall(sayings_match.group(1)):
            key = "say." + ident
            used.add(key)
            if key not in strings:
                failures.append(f"WS2SilentCopy.sayings: 缺键 {key}")
            elif json.loads('"%s"' % source) != zh[key]:
                failures.append(f"WS2SilentCopy.sayings: {key} 的中文和表里不同")

    # 防漏网扫描（§9.4，第28批加）：全 prototype/ 的中文字符串字面量行数不得超过棘轮基线。
    # 基线 = 第28批完成静音线迁移后的实况（3888），冻结在 tests/localizable-ratchet.json；
    # 后续批次每迁一个表面就调低，只许降不许升。身份表（WS2SilentCopy/WS2SettingsInfo/生成的
    # WS2PrivacyData）、QA 探针、权限名等仍占位数，逐批甄别消化。
    ratchet_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "localizable-ratchet.json")
    ratchet = 3888
    if os.path.isfile(ratchet_path):
        ratchet = json.load(open(ratchet_path, encoding="utf-8"))["han_literal_lines"]
    han_lines = 0
    HAN_SEARCH = HAN_RE.search
    for path in swift_files(root):
        for line in open(path, encoding="utf-8"):
            stripped = line.lstrip()
            if stripped.startswith("//"):
                continue
            code = line.split("//")[0]
            if '"' in code and HAN_SEARCH(code):
                han_lines += 1
    if han_lines > ratchet:
        failures.append(f"防漏网：中文字面量行数 {han_lines} 超过棘轮基线 {ratchet}（迁移只许降不许升）")
    else:
        print(f"防漏网扫描：{han_lines} 行（基线 {ratchet}）")

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
