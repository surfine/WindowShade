#!/usr/bin/env python3
"""按 Sparkle 的规则比较两个 build 号（CFBundleVersion / sparkle:version）。

用法：scripts/build-version-compare.py <a> <b>
输出：1（a 较大）、0（相同）、-1（a 较小）；参数不是「数字与点」就退回 2 并说明。

为什么要有这支：2026-11-10 实测 repo 里的 Sparkle 2.10.0，
`20261110-01` 和 `20261110-02` 被 `SUStandardVersionComparator` 判成**相同**——
同一天发第二个包，已装的人就永远收不到更新。点号没有这个问题。
所以 build 号只用「数字与点」，这里也按同一套规则逐段比数字：
分段后短的补 0，逐段比较，全相同就是相同。纯数字与点的情况下，
这和 Sparkle 的结果逐项一致（tests/run-build-version-tests.sh 对照 Sparkle 本体）。
"""
import re
import sys

SHAPE = re.compile(r"^[0-9]+(\.[0-9]+)*$")


def compare(a: str, b: str) -> int:
    if a == b:
        return 0
    pa = [int(x) for x in a.split(".")]
    pb = [int(x) for x in b.split(".")]
    for i in range(max(len(pa), len(pb))):
        x = pa[i] if i < len(pa) else 0
        y = pb[i] if i < len(pb) else 0
        if x != y:
            return 1 if x > y else -1
    return 0


def main() -> int:
    args = [a.strip() for a in sys.argv[1:]]
    if args and args[0] == "--max":
        values = args[1:]
        if not values:
            return 0
        for value in values:
            if not SHAPE.match(value):
                print("build 号「" + value + "」不是「数字与点」（例如 20261110.01）。", file=sys.stderr)
                return 2
        best = values[0]
        for value in values[1:]:
            if compare(value, best) > 0:
                best = value
        print(best)
        return 0
    if len(args) != 2:
        print("usage: build-version-compare.py <a> <b> | --max <a> <b> …", file=sys.stderr)
        return 2
    a, b = args
    for value in (a, b):
        if not SHAPE.match(value):
            print("build 号「" + value + "」不是「数字与点」（例如 20261110.01）。"
                  "连字号会让 Sparkle 把同一天的包看成同一个版本。", file=sys.stderr)
            return 2
    print(compare(a, b))
    return 0


if __name__ == "__main__":
    sys.exit(main())
