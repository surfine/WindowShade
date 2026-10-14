#!/usr/bin/env python3
"""生成 WS2SettingsInfo.shortHant（繁体短副标题表）。

从简体 short 表（简体全文 → 简体短句）与目录里的 zh-Hans/zh-Hant 对照生成：
    繁体全文 → 繁体短句
键用繁体全文，和 short 表用简体全文做键是对称的；运行时按当前语言的全文查。

用法：python3 tools/localize/short-hant.py     # 就地重写 Swift 里 shortHant 表体
"""
import importlib.util
import json
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "prototype", "App", "WS2SettingsInfo.swift")
CATALOG = os.path.join(ROOT, "prototype", "Resources", "Localizable.xcstrings")

# 短句本身不一定是目录里的整句，直接走 zh-hant.py 的转换流水线。
_spec = importlib.util.spec_from_file_location("zh_hant", os.path.join(os.path.dirname(__file__), "zh-hant.py"))
zh_hant = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(zh_hant)


def to_traditional(text):
    """单句简→繁（与 zh-hant.py 同一套规则）。"""
    return zh_hant.convert_to_traditional([text])[0]


def main():
    source = open(SOURCE, encoding="utf-8").read()
    catalog = json.load(open(CATALOG, encoding="utf-8"))["strings"]

    short_body = re.search(r'static let short: \[String:String\] = \[(.*?)\n    \]', source, re.S).group(1)
    short_pairs = re.findall(r'"((?:[^"\\]|\\.)*)": "((?:[^"\\]|\\.)*)"', short_body)

    by_hans = {}
    for key, entry in catalog.items():
        loc = entry.get("localizations", {})
        hans = loc.get("zh-Hans", {}).get("stringUnit", {}).get("value")
        hant = loc.get("zh-Hant", {}).get("stringUnit", {}).get("value")
        if hans and hant:
            by_hans[hans] = hant

    rows, skipped = [], []
    for hans, short_value in short_pairs:
        hant_full = by_hans.get(hans)
        if not hant_full:
            skipped.append(hans)
            continue
        rows.append((hant_full, to_traditional(short_value)))

    print(f"生成 {len(rows)} 条，跳过 {len(skipped)} 条（目录里没有对应的简体全文）", flush=True)
    for text in skipped:
        print("   跳过:", text[:32])

    block = "\n".join(f'        "{a}": "{b}",' for a, b in rows)
    # 只吃掉 shortHant 表体：从声明行到它自己的收尾 `]`（不要把下一张表也吞了）。
    pattern = re.compile(r'(nonisolated static let shortHant: \[String: String\] = \[).*?(\n    \]\n)', re.S)
    if not pattern.search(source):
        raise SystemExit("在 WS2SettingsInfo.swift 里找不到 shortHant 表（先手工建空表）")
    source = pattern.sub(lambda m: m.group(1) + "\n" + block + m.group(2), source, count=1)
    open(SOURCE, "w", encoding="utf-8").write(source)
    print("已写入短句表")


if __name__ == "__main__":
    main()
