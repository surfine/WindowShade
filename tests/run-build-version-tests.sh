#!/bin/bash
# build 号的比较规则必须和 Sparkle 本体一致。
# 2026-11-10 实测：`20261110-01` 和 `20261110-02` 被 SUStandardVersionComparator 判成相同，
# 所以 build 号只用「数字与点」；这支测试把 scripts/build-version-compare.py 逐项对过 Sparkle。
set -euo pipefail
cd "$(dirname "$0")/.."
work=.build/build-version-tests
mkdir -p "$work"

cat > "$work/sparkle.swift" <<'EOF'
import Foundation
import Sparkle

// 两边都要能比较：纯整数（旧 build）、日期点号（新 build）、对外版本号。
let pairs = [
    ("21", "20"), ("20261110.01", "20261110.02"), ("20261110.02", "20261110.01"),
    ("20261110.01", "21"), ("20261110.10", "20261110.01"),
    ("20261110.1", "20261110.01"), ("2026111001", "2026111002"),
    ("20261110.01", "2026111001"), ("1.0.21.1", "1.0.21"), ("20261110.01", "20261110.01"),
]
let c = SUStandardVersionComparator.default
for (a, b) in pairs {
    print("\(a) \(b) \(c.compareVersion(a, toVersion: b).rawValue)")
}
EOF

swiftc -O "$work/sparkle.swift" -F prototype/Vendor -framework Sparkle -o "$work/sparkle"
DYLD_FRAMEWORK_PATH="$(pwd)/prototype/Vendor" "$work/sparkle" > "$work/sparkle.txt"

failures=0
while read -r a b want; do
    got=$(python3 -I scripts/build-version-compare.py "$a" "$b")
    if [ "$got" != "$want" ]; then
        echo "FAIL: $a vs $b — Sparkle 说 $want，我们算 $got"
        failures=$((failures + 1))
    fi
done < "$work/sparkle.txt"

# 连字号必须被拒绝：它会让同一天的第二个包收不到更新。
if python3 -I scripts/build-version-compare.py 20261110-01 20261110-02 >/dev/null 2>&1; then
    echo "FAIL: 连字号没有被拒绝"
    failures=$((failures + 1))
fi

# 取最大值的入口也要和逐项比较一致。
best=$(python3 -I scripts/build-version-compare.py --max 21 20 20261110.02 20261110.01)
if [ "$best" != "20261110.02" ]; then
    echo "FAIL: --max 取到 $best，应为 20261110.02"
    failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
    echo "FAIL: build 号比较有 $failures 项和 Sparkle 不一致"
    exit 1
fi
echo "PASS: build 号比较与 Sparkle 逐项一致，连字号被拒绝，--max 与逐项比较一致"
