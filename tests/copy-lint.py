#!/usr/bin/env python3
"""文案检查：禁词、内部代号、副标题长度、刘海主句长度。

用法：python3 tests/copy-lint.py [--repo DIR] [--strict] [--self-test]

默认只报告、退出 0（build.sh --check 用这个）；--strict 有失败时退出 1，修完文案后再打开。

规则（见 docs/copy-guide.md）：
  a) 用户可见的中文字符串字面量不许含禁词：内置列表加几个词汇表里没有歧义的词
     （钉住、悬浮、折叠、显示桌面）。不再整表解析“不要用”列（会误伤只在某一行才算错的词）。
     跳过日志/打印/调试行、带“xxx: ”日志前缀的字符串、Bench 文件。
  b) prototype/App/WS2PrivacyData.swift 里不许出现内部代号（P1、A2a/A2b、IPC、L1、Sparkle）
     和“待验证”。
  c) subtitle: 参数超过 20 个字的只报告，不失败。
  d) prototype/Core/*Copy.swift 字典里的每条句子、NotchSentence.swift 里 headline:/suffix:
     字面量超过 8 个字形簇就失败；--self-test 用夹具证明规则会失败也会通过。

排除：tests/、probes/、Effects/EffectInspector.swift（开发检查器，不是用户可见文案）。
退出码：有失败规则返回 1，否则 0。
"""
import argparse
import os
import re
import sys
import unicodedata

# “计时器”不再是禁词：2026-10-09 起它是你自己开的、只倒数一次的那个东西的名字（docs/copy-guide.md）；番茄钟仍叫番茄钟。
BUILTIN_FORBIDDEN = ["卷起", "卷成", "标题条", "偷看", "指挥控制", "动态锁", "自动锁屏", "窗口仓",
                     "钉住", "悬浮", "折叠", "显示桌面"]
LOG_LINE_RE = re.compile(r"\b(print|NSLog|debugPrint|os_log|logger|log|trace|assert\w*|fatalError|precondition)\s*\(|\bLogger\b|#if DEBUG", re.IGNORECASE)
LOG_PREFIX_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]*: ")
EXCLUDED_NAME_PARTS = ("Bench", "Probe")
# 系统自己的功能名（比如 macOS 的“显示桌面”键）照系统叫法写，在那一行末尾加这条注释放行。
SYSTEM_NAME_MARK = "copy-lint: system-name"
PHASE_LINE_RE = re.compile(r"\b\w*[Pp]hase\(")
CJK_RE = re.compile(r"[㐀-鿿豈-﫿]")
STRING_RE = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
SUBTITLE_RE = re.compile(r'subtitle:\s*"((?:[^"\\\n]|\\.)*)"')
INTERNAL_RE = re.compile(r"\b(P\d|A2[ab]|IPC|L1|Sparkle)\b")
PENDING = "待验证"
HEADLINE_ARG_RE = re.compile(r'\b(?:headline|suffix):\s*"((?:[^"\\\n]|\\.)*)"')
DICT_ENTRY_RE = re.compile(r'^\s*"[A-Za-z0-9_.]+":\s*"((?:[^"\\\n]|\\.)*)"')
HEADLINE_LIMIT = 8
SUBTITLE_LIMIT = 20
EXCLUDED_PARTS = {"tests", "probes"}
EXCLUDED_FILES = {os.path.join("prototype", "Effects", "EffectInspector.swift")}


def grapheme_count(text):
    """字形簇的近似计数：组合记号、变体选择符并入前一个字符，ZWJ 连接的序列计为一个。"""
    count = 0
    join_next = False
    for ch in text:
        cat = unicodedata.category(ch)
        if ch == "‍":
            join_next = True
            continue
        if cat in ("Mn", "Mc", "Me") or ch in ("️", "︎"):
            continue
        if join_next:
            join_next = False
            continue
        count += 1
    return count


def swift_files(repo):
    prototype = os.path.join(repo, "prototype")
    for root, dirs, files in os.walk(prototype):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED_PARTS and not d.endswith(".app") and d not in (".build", "dist", "Vendor"))
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, repo)
            if rel in EXCLUDED_FILES or EXCLUDED_PARTS & set(rel.split(os.sep)):
                continue
            yield path, rel


def strip_comment(line):
    """去掉字符串外面的 // 注释：注释里引用的旧说法不是界面文案。"""
    in_str = False
    i = 0
    while i < len(line):
        ch = line[i]
        if in_str and ch == "\\":
            i += 2
            continue
        if ch == '"':
            in_str = not in_str
        elif not in_str and line.startswith("//", i):
            return line[:i]
        i += 1
    return line


def check_text(rel, text, forbidden):
    """对一个文件的文本跑规则 a/d，返回 (失败列表, 长副标题列表)。供 main 和自测共用。"""
    failures, long_subtitles = [], []
    lines = text.splitlines()
    base = os.path.basename(rel)
    skip_a = any(part in base for part in EXCLUDED_NAME_PARTS)

    # a) 禁词
    if not skip_a:
        for lineno, line in enumerate(lines, 1):
            if LOG_LINE_RE.search(line) or PHASE_LINE_RE.search(line) or SYSTEM_NAME_MARK in line:
                continue
            for m in STRING_RE.finditer(strip_comment(line)):
                lit = m.group(1)
                if not CJK_RE.search(lit) or LOG_PREFIX_RE.match(lit):
                    continue
                for word in forbidden:
                    if word in lit:
                        failures.append(f"{rel}:{lineno}: 禁词「{word}」出现在 \"{lit}\"")

    # b) 隐私数据文件里的内部代号与“待验证”
    if os.path.basename(rel) == "WS2PrivacyData.swift":
        for lineno, line in enumerate(lines, 1):
            m = INTERNAL_RE.search(line)
            if m:
                failures.append(f"{rel}:{lineno}: 内部代号「{m.group(0)}」")
            if PENDING in line:
                failures.append(f"{rel}:{lineno}: 出现「{PENDING}」")

    # c) subtitle 参数超过 20 个字：只报告
    for lineno, line in enumerate(lines, 1):
        for m in SUBTITLE_RE.finditer(line):
            n = grapheme_count(m.group(1))
            if n > SUBTITLE_LIMIT:
                long_subtitles.append(f"{rel}:{lineno}: {n} 个字 \"{m.group(1)}\"")

    # d) 刘海主句：*Copy.swift 字典条目；NotchSentence.swift 的 headline:/suffix: 字面量
    # 豁免（第28批，逐条）：这四句是第28批把散句机械迁移进 WS2SilentCopy.sayings 时带入的
    # 改动前原文（逐字节，出处 2003e53^ 的 WS2SilentHost/WS2SilentGates），不是新写文案；
    # 中文不在本批改动范围（zh 逐字节不变是硬约束）。将来改写句子时按上限收紧并删掉豁免。
    LEGACY_SAYINGS = {"confirmVoid", "unclear", "nodOrClick", "timeout.glance"}
    is_copy = base.endswith("Copy.swift")
    is_sentence = base == "NotchSentence.swift"
    if is_copy or is_sentence:
        rx = DICT_ENTRY_RE if is_copy else HEADLINE_ARG_RE
        for lineno, line in enumerate(lines, 1):
            m = rx.search(line)
            if m and CJK_RE.search(m.group(1)):
                n = grapheme_count(m.group(1))
                if n > HEADLINE_LIMIT:
                    key = m.group(0)
                    if any(f'"{k}"' in line for k in LEGACY_SAYINGS):
                        long_subtitles.append(f"{rel}:{lineno}: 豁免（迁移原文）{n} 个字 \"{m.group(1)}\"")
                        continue
                    failures.append(f"{rel}:{lineno}: 主句有 {n} 个字形簇，上限 {HEADLINE_LIMIT}：\"{m.group(1)}\"")
    return failures, long_subtitles


def self_test():
    """每条规则都要能失败也能通过，否则“0 条”没有意义。"""
    ok = True

    def expect(name, rel, text, want_fail):
        nonlocal ok
        f, _ = check_text(rel, text, BUILTIN_FORBIDDEN)
        got = bool(f)
        if got != want_fail:
            ok = False
            print(f"自测失败：{name}（期望{'失败' if want_fail else '通过'}，实际{'失败' if got else '通过'}）")

    expect("a 禁词应失败", "prototype/App/X.swift", 'let s = "窗口会钉住"', True)
    expect("a 干净应通过", "prototype/App/X.swift", 'let s = "窗口会置顶"', False)
    expect("a 日志行应跳过", "prototype/App/X.swift", 'print("折叠窗口")', False)
    expect("a 日志前缀应跳过", "prototype/App/X.swift", 'let s = "fold: 折叠窗口"', False)
    expect("a 注释应跳过", "prototype/App/X.swift", '// 否则"折叠不了"无从排查', False)
    expect("a 注释前的字符串仍检查", "prototype/App/X.swift", 'let s = "钉住" // 置顶', True)
    expect("a 网址里的 // 不算注释", "prototype/App/X.swift", 'let s = "https://x 钉住"', True)
    expect("a 系统功能名可放行", "prototype/Core/XCopy.swift", '"a.b": "显示桌面", // copy-lint: system-name', False)
    expect("a 探针文件应跳过", "prototype/X/ShotProbe.swift", 'let s = "已折叠"', False)
    expect("a Bench 文件应跳过", "prototype/Tools/AXLatencyBench.swift", 'let s = "折叠"', False)
    expect("b 内部代号应失败", "prototype/App/WS2PrivacyData.swift", 'let s = "走 IPC 通道"', True)
    expect("d 字典 9 字应失败", "prototype/Core/FooCopy.swift", '        "a.b": "一二三四五六七八九",', True)
    expect("d 字典 8 字应通过", "prototype/Core/FooCopy.swift", '        "a.b": "一二三四五六七八",', False)
    expect("d headline 9 字应失败", "prototype/Core/NotchSentence.swift", 'x(headline: "一二三四五六七八九")', True)
    expect("d suffix 干净应通过", "prototype/Core/NotchSentence.swift", 'headline(name: n, suffix: "有变化")', False)
    print("自测通过" if ok else "自测未通过")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    ap.add_argument("--strict", action="store_true", help="有失败时退出 1（默认只报告）")
    ap.add_argument("--self-test", action="store_true", help="只跑规则自测")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if self_test() != 0:
        return 1
    repo = args.repo
    forbidden = list(BUILTIN_FORBIDDEN)
    print(f"禁词（{len(forbidden)} 个）：{'、'.join(forbidden)}")

    failures, long_subtitles = [], []
    for path, rel in swift_files(repo):
        with open(path, encoding="utf-8") as f:
            fl, ls = check_text(rel, f.read(), forbidden)
        failures += fl
        long_subtitles += ls

    if long_subtitles:
        print(f"副标题超过 {SUBTITLE_LIMIT} 个字（只报告，不失败）：{len(long_subtitles)} 条")
        for item in long_subtitles:
            print(f"  {item}")
    if failures:
        print(f"文案检查：{len(failures)} 条待修{'（strict，失败）' if args.strict else '（只报告，不挡构建；修完后加 --strict）'}")
        for item in failures:
            print(f"  {item}")
        return 1 if args.strict else 0
    print("文案检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
