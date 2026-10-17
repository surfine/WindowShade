#!/usr/bin/env python3
"""设置搜索的索引门禁：行构造器用到的每个 settings.*.name 键都进了搜索索引。

两步：
1. 静态（总跑）：行文字的挂牌点还在——WS2SettingsCopy.content 的三个入口都调 SettingsSearchRegistry.register
   （所有页的行构造器都经过它，见 prototype/App/SettingsSearchIndex.swift 文件头）；再从源码里收出行构造器
   （makeUnified*Row、makeToggleRow、makeControlRow、makeActionRow、makeUnifiedLabels）调用里的 settings.*.name 键。
2. 对照（有索引转储时跑）：tests/SettingsNavigationTests.swift 建好整个设置窗口后，把收到的索引写到
   .build/appkit-tests/settings-search-index.json；这里逐个核对第 1 步收出的键（或它的简体源句）都在里面。
   没有转储时只做第 1 步并说明；--require-index 时没有转储算失败。

用法：python3 tests/check-settings-search-index.py --repo . [--index FILE] [--require-index]
"""
import argparse
import json
import os
import re
import sys

BUILDERS = ("makeUnifiedToggleRow", "makeUnifiedControlRow", "makeUnifiedPermissionRow",
            "makeToggleRow", "makeControlRow", "makeActionRow", "makeUnifiedLabels")
CALL_RE = re.compile(r"\b(%s)\(" % "|".join(BUILDERS))
KEY_RE = re.compile(r'WSL10n\.(?:text|setting)\(\s*"(settings\.[A-Za-z0-9_.]+\.name)"\s*,\s*zh:\s*("(?:[^"\\\n]|\\.)*")?')

# 只在某个状态下才建的行（测试进程里那个状态不成立）：键 → 为什么不在转储里。
# 转储是在“WindowShade 2 预览旗标开、别的开关都是默认值”的进程里收的。
CONDITIONAL = {
}


def call_args(text, start):
    """从 '(' 之后起，取到配对的 ')' 为止。"""
    depth, i = 1, start
    in_string = False
    while i < len(text) and depth:
        c = text[i]
        if in_string:
            if c == "\\":
                i += 1
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        i += 1
    return text[start:i - 1]


def builder_keys(root):
    keys = {}
    for base, dirs, files in os.walk(os.path.join(root, "prototype")):
        dirs[:] = [d for d in dirs if d not in (".build", "Vendor", "dist", "WindowShade.app")]
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(base, name)
            text = open(path, encoding="utf-8").read()
            for match in CALL_RE.finditer(text):
                # 跳过定义（func makeX(）
                if text[max(0, match.start() - 5):match.start()].endswith("func "):
                    continue
                args = call_args(text, match.end())
                for key_match in KEY_RE.finditer(args):
                    key = key_match.group(1)
                    zh = json.loads(key_match.group(2)) if key_match.group(2) and "\\(" not in key_match.group(2) else None
                    keys.setdefault(key, (zh, os.path.relpath(path, root)))
    return keys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    parser.add_argument("--index")
    parser.add_argument("--require-index", action="store_true")
    args = parser.parse_args()
    root = os.path.abspath(args.repo)
    failures = []

    info = open(os.path.join(root, "prototype", "App", "WS2SettingsInfo.swift"), encoding="utf-8").read()
    hooks = info.count("SettingsSearchRegistry.register(")
    if hooks < 3:
        failures.append(f"WS2SettingsCopy.content 的三个入口要各调一次 SettingsSearchRegistry.register（现在 {hooks} 处）")

    keys = builder_keys(root)
    if len(keys) < 30:
        failures.append(f"从行构造器里只收出 {len(keys)} 个 settings.*.name 键，调用写法变了？")

    index_path = args.index or os.path.join(root, ".build", "appkit-tests", "settings-search-index.json")
    if os.path.isfile(index_path):
        entries = json.load(open(index_path, encoding="utf-8"))
        indexed_keys = {e.get("key") for e in entries if e.get("key")}
        indexed_names = {n for e in entries for n in e.get("names", [])}
        missing = []
        for key, (zh, where) in sorted(keys.items()):
            if key in indexed_keys or (zh and zh in indexed_names) or key in CONDITIONAL:
                continue
            missing.append(f"{key}（{zh or '?'}，{where}）")
        if missing:
            failures.append("这些行构造器的键没进搜索索引：\n  " + "\n  ".join(missing))
        stale = [k for k in CONDITIONAL if k not in keys]
        if stale:
            failures.append(f"CONDITIONAL 里有已经不用的键：{stale}")
        checked = f"对照 {os.path.relpath(index_path, root)}（{len(entries)} 行）"
    elif args.require_index:
        failures.append(f"没有索引转储 {index_path}：先跑 bash tests/run-appkit-tests.sh SettingsNavigationTests")
        checked = "没有索引转储"
    else:
        checked = "没有索引转储，只做了静态检查（跑 bash tests/run-appkit-tests.sh SettingsNavigationTests 生成）"

    if failures:
        for failure in failures:
            print("FAIL:", failure)
        sys.exit(1)
    print(f"设置搜索索引检查通过：{len(keys)} 个行构造器键；{checked}")


if __name__ == "__main__":
    main()
