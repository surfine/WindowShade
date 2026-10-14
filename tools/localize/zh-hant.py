#!/usr/bin/env python3
"""把目录里的简体源句转成台湾用语的繁体（zh-Hant）列。

用法：
    python3 tools/localize/zh-hant.py            # 写入 prototype/Resources/Localizable.xcstrings
    python3 tools/localize/zh-hant.py --audit    # 只报告：转换结果里还剩哪些大陆用词

流程：每条 zh-Hans → OpenCC `s2twp`（简体→繁体 + 台湾用词）→ 套本文件的台湾专名表
（Apple 台湾官方用词与我们自己的产品词，OpenCC 不认识或译错的那批）→ 写 zh-Hant 列。

前置：opencc CLI（brew install opencc）。
新增文案入库后重跑本脚本即可，不用手改 xcstrings 的 zh-Hant 列。
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CATALOG = os.path.join(ROOT, "prototype", "Resources", "Localizable.xcstrings")

# 台湾专名表：OpenCC s2twp 的输出 → 台湾实际用词。
# 分三类：① Apple 台湾官方界面术语（OpenCC 不认识或给的是大陆式译法）；
# ② Mac 通用部件的台湾叫法；③ 我们自己的产品词在台湾的写法。
# 顺序无关（按 needle 长度从长到短替换），但同一处多次命中时以更长的为准。
TAIWAN_TERMS = [
    # ① Apple 台湾官方术语
    ("排程中心", "指揮中心"),        # Mission Control
    ("選單欄", "選單列"),            # menu bar
    ("標題欄", "標題列"),            # title bar（台湾 Apple 用「列」）
    ("狀態欄", "狀態列"),
    ("全屏", "全螢幕"),
    ("畫中畫", "子母畫面"),          # Picture in Picture
    ("輔助功能", "輔助使用"),        # Accessibility
    ("快捷鍵", "快速鍵"),            # keyboard shortcut
    ("雙擊", "按兩下"),
    ("三擊", "按三下"),
    ("單擊", "按一下"),
    ("拖動", "拖移"),
    ("拖拽", "拖移"),
    ("訪問", "存取"),
    ("鎖屏", "鎖定畫面"),            # lock screen
    ("塊屏", "塊螢幕"),              # 「这块屏」= this display
    ("內建屏", "內建螢幕"),
    ("會話", "工作階段"),            # session
    ("外設", "周邊裝置"),            # peripheral
    ("許可權", "權限"),              # OpenCC 的错译：permission → 權限
    ("訪達", "Finder"),              # Finder 在台湾不译
    ("這臺", "這台"),                # 台湾 Apple 写「台」（台灣/這台 Mac）
    ("臺", "台"),                    # 其余「臺」同此（啟動台已单独处理）
    ("配置", "設定"),                # configuration → 設定（台湾）
    ("手柄", "手把"),                # game controller（台湾叫手把）
    ("搖桿", "搖桿"),                # 台湾也用「搖桿」，保留
    ("在Finder中顯示", "在 Finder 中顯示"),
    ("反饋", "回饋"),
    ("認證", "驗證"),                # authentication
    ("應用程序", "應用程式"),
    ("硬盤", "硬碟"),
    ("優盤", "隨身碟"),
    ("打印機", "印表機"),
    ("鼠標", "滑鼠"),                # 兜底，正常 OpenCC 已换
    ("隱私", "隱私權"),              # 台湾系统设置的页面名（隱私權與安全性）
    ("隔空投送", "AirDrop"),         # 台湾不译这个名字
    ("隔空播放", "AirPlay"),
    ("負一屏", "主畫面最左邊那一頁"),
    ("分屏", "分割畫面"),            # Split View 的台湾叫法
    ("屏", "螢幕"),                  # 其余单字「屏」都是"屏幕"义（半屏/这块屏/锁屏已先处理）
    # ② Mac 部件
    ("窗口", "視窗"),
    ("程序塢", "Dock"),
    ("程式塢", "Dock"),
    ("廢紙簍", "垃圾桶"),
    ("觸摸板", "觸控板"),
    ("妙控鼠標", "巧控滑鼠"),
    ("妙控滑鼠", "巧控滑鼠"),
    ("妙控鍵盤", "巧控鍵盤"),
    ("妙控板", "巧控板"),
    # ③ 产品词
    ("劉海", "瀏海"),                # notch（头发那个词，台湾 Apple 也用它指刘海）
    ("啟動臺", "啟動台"),            # Launchpad
    ("魔法平鋪", "魔法並排"),
    ("捲簾條", "捲簾條"),            # 确认写法（OpenCC 已对）
]

# 审计用：出现即说明这条还没换成台湾说法（排除我们有意保留的写法）。
AUDIT_WORDS = [
    "窗口", "選單欄", "默認", "設置", "快捷鍵", "單擊", "雙擊", "全屏",
    "畫中畫", "妙控", "隱私(?!權)", "輔助功能", "鼠標", "軟件", "網絡", "信息",
    "文件夾", "打印", "磁盤", "視頻", "屏幕", "優盤",
]


def convert(texts):
    """批量走 opencc s2twp；用哨兵保住换行。"""
    sentinel = "\x00"
    lines = [t.replace("\r\n", "\n").replace("\n", sentinel) for t in texts]
    with tempfile.NamedTemporaryFile("w+", suffix=".txt", delete=False, encoding="utf-8") as handle:
        handle.write("\n".join(lines))
        path = handle.name
    try:
        out = subprocess.run(["opencc", "-c", "s2twp", "-i", path],
                             capture_output=True, text=True, check=True).stdout
    finally:
        os.unlink(path)
    result = out.split("\n")
    if result and result[-1] == "":
        result.pop()
    if len(result) != len(texts):
        raise SystemExit(f"opencc 行数不匹配：{len(result)} != {len(texts)}")
    return [r.replace(sentinel, "\n") for r in result]


def apply_terms(text):
    for source, target in sorted(TAIWAN_TERMS, key=lambda pair: -len(pair[0])):
        if source != target:
            text = text.replace(source, target)
    return text


def convert_to_traditional(texts):
    """整条流水线：OpenCC s2twp + 台湾专名表。别的脚本（short-hant.py）也用它。"""
    return [apply_terms(t) for t in convert(texts)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", action="store_true", help="只报告残留大陆用词，不写文件")
    args = parser.parse_args()

    data = json.load(open(CATALOG, encoding="utf-8"))
    strings = data["strings"]
    keys = [k for k, entry in strings.items() if "zh-Hans" in entry.get("localizations", {})]
    sources = [strings[k]["localizations"]["zh-Hans"]["stringUnit"]["value"] for k in keys]

    converted = [apply_terms(t) for t in convert(sources)]

    if args.audit:
        hits = {}
        for key, text in zip(keys, converted):
            for word in AUDIT_WORDS:
                if re.search(word, text):
                    hits.setdefault(word, []).append((key, text))
        for word, items in sorted(hits.items(), key=lambda kv: -len(kv[1])):
            print(f"{word}: {len(items)} 处")
            for key, text in items[:3]:
                print(f"    {key}: {text}")
        print(f"\n合计 {len(keys)} 条，含待查用词的 {len({k for v in hits.values() for k, _ in v})} 条")
        return

    for key, value in zip(keys, converted):
        localizations = strings[key]["localizations"]
        localizations["zh-Hant"] = {"stringUnit": {"state": "translated", "value": value}}
    json.dump(data, open(CATALOG, "w", encoding="utf-8"), ensure_ascii=False, indent=2,
              separators=(",", " : "))
    print(f"写入 zh-Hant：{len(keys)} 条", file=sys.stderr)


if __name__ == "__main__":
    main()
