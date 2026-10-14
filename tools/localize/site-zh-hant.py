#!/usr/bin/env python3
"""生成官网的简体→台湾繁体对照表（site/scripts/zh-hant.json）。

官网文案散在 content.mjs（一个 copy 对象）与 history.mjs（大量 t('中文','English')）
里，没有 xcstrings 那样的目录。这里把两处的中文串抽出来，走 App 那套流水线
（opencc s2twp + 台湾专名表，见 tools/localize/zh-hant.py）转好，写成一个
「中文原文 → 繁体」的查表文件；站点构建时按串查表（查不到就原样输出简体）。

用法：python3 tools/localize/site-zh-hant.py
"""
import importlib.util
import json
import os
import re
import subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SITE = os.path.join(ROOT, "site", "scripts")
OUT = os.path.join(SITE, "zh-hant.json")

_spec = importlib.util.spec_from_file_location("zh_hant", os.path.join(os.path.dirname(__file__), "zh-hant.py"))
zh_hant = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(zh_hant)

HAN = re.compile(r"[\u4e00-\u9fff]")


def strings_from_copy():
    """把 content.mjs 的 copy.zh 里的所有字符串（含嵌套）交给 node 打出来。"""
    script = (
        "import('./site/scripts/content.mjs').then(m => {"
        "  const out = [];"
        "  const walk = (v) => {"
        "    if (typeof v === 'string') out.push(v);"
        "    else if (Array.isArray(v)) v.forEach(walk);"
        "    else if (v && typeof v === 'object') Object.values(v).forEach(walk);"
        "  };"
        "  walk(m.copy.zh);"
        "  process.stdout.write(JSON.stringify(out));"
        "});"
    )
    raw = subprocess.run(["node", "-e", script], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return json.loads(raw)


def strings_from_all_site_scripts():
    """站点脚本里所有含汉字的字符串字面量（单引号/双引号/反引号）——launchpad.mjs
    这类模块的文案不经过 copy 对象，也要收进来。"""
    import glob
    found = []
    for path in sorted(glob.glob(os.path.join(SITE, "*.mjs")) + glob.glob(os.path.join(ROOT, "site", "*.js"))):
        source = open(path, encoding="utf-8").read()
        for match in re.finditer(r"'((?:[^'\\\n]|\\.)*)'" + '|' + r'"((?:[^"\\\n]|\\.)*)"', source):
            text = match.group(1) if match.group(1) is not None else match.group(2)
            if text and HAN.search(text):
                found.append(text.replace("\\'", "'").replace('\\"', '"'))
    return found


def strings_from_history():
    """history.mjs 的中文都在 t('中文', 'English') 的第一个参数里。"""
    source = open(os.path.join(SITE, "history.mjs"), encoding="utf-8").read()
    found = []
    # t('…', '…')：单引号串，允许转义
    for match in re.finditer(r"\bt\(\s*'((?:[^'\\]|\\.)*)'\s*,", source):
        found.append(match.group(1).replace("\\'", "'").replace("\\\\", "\\"))
    # 少量直接写在模板里的中文（regex 兜底：任何带汉字、长度 >1 的字面量）
    for match in re.finditer(r"'((?:[^'\\]|\\.)*)'", source):
        text = match.group(1)
        if HAN.search(text) and len(text) > 1 and text not in found:
            found.append(text)
    return found


def main():
    texts = strings_from_copy() + strings_from_history() + strings_from_all_site_scripts()
    # 只留带汉字、且不重复的
    unique = []
    seen = set()
    for text in texts:
        if not HAN.search(text) or text in seen:
            continue
        seen.add(text)
        unique.append(text)
    converted = zh_hant.convert_to_traditional(unique)
    mapping = {zh: tw for zh, tw in zip(unique, converted) if zh != tw}
    json.dump(mapping, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
    print(f"抽出 {len(unique)} 条中文串，其中 {len(mapping)} 条与繁体不同，写入 {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
