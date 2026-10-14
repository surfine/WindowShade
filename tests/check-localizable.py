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
# 常见的「只有简体才这么写」的字。台湾译文里出现任何一个，就是没转换或手改漏了。
# 只收字形不同的常用字，不收两岸同形的字（那会误报）。
SIMPLIFIED_ONLY_CHARS = "设认语关无发时门务软网动这为于会过还后没边块让换录拟读写较级处应对开长点标题栏屏隐营销"
SIMPLIFIED_ONLY_RE = re.compile(f"[{SIMPLIFIED_ONLY_CHARS}]")


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
        for lang in ("zh-Hans", "zh-Hant", "en"):
            value = loc.get(lang, {}).get("stringUnit", {}).get("value", "")
            if not value:
                failures.append(f"{key}: 缺 {lang} 译文")
            values[lang] = value
        for lang in ("zh-Hant", "en"):
            if values["zh-Hans"].count("%@") != values[lang].count("%@"):
                failures.append(f"{key}: zh-Hans 和 {lang} 的 %@ 个数不同")
        if HAN_RE.search(values["en"]):
            failures.append(f"{key}: en 译文里有汉字（漏译或抄了中文）")
        # 繁体防线：台湾译文里不该再出现只在简体里用的字（挑一批高频简体字兜底；
        # 目录由 tools/localize/zh-hant.py 生成，这里防的是手改与将来新文案漏转）。
        stray = SIMPLIFIED_ONLY_RE.search(values["zh-Hant"])
        if stray:
            failures.append(f"{key}: zh-Hant 里有简体字 {stray.group(0)!r}（zh-Hant: {values['zh-Hant']!r}）")
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
    # 基线冻结在 tests/localizable-ratchet.json，只许降不许升。
    # 口径（2026-10-13 修正）：只数**没走目录的裸中文字面量**——`WSL10n.text/setting(zh:)`
    # 里的中文是语义身份源句，显示已经走目录出当前语言，不该算漏网。旧口径把它们也计入，
    # 结果是"把行迁进目录"反而让计数上涨（第30批设置面板迁移实测：本页 66 → 5 行裸字面量，
    # 旧口径总数却 +38，全是被计入的身份源句）。证据：docs/design-review/2026-10-13-settings-panel/README.md。
    # 身份表（WS2SettingsInfo 的 short 表等）、生成的 WS2PrivacyData、QA 探针、权限名等仍占位数，逐批消化。
    ratchet_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "localizable-ratchet.json")
    ratchet = 3888
    if os.path.isfile(ratchet_path):
        ratchet = json.load(open(ratchet_path, encoding="utf-8"))["han_literal_lines"]
    han_lines = 0
    HAN_SEARCH = HAN_RE.search
    WSL10N_LINE = re.compile(r"WSL10n\.(?:text|setting)\(")
    for path in swift_files(root):
        for line in open(path, encoding="utf-8"):
            stripped = line.lstrip()
            if stripped.startswith("//"):
                continue
            code = line.split("//")[0]
            if '"' in code and HAN_SEARCH(code) and not WSL10N_LINE.search(code):
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
