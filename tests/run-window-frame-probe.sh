#!/bin/bash
# 规格 R7 真实核对（手动跑，要辅助功能权限，屏幕上会闪两扇窗口约 10 秒）：
# 起夹具 → 读一扇窗的 AX 外框 → kill -STOP 冻住夹具 → AX 读不到时回退链给出的外框应与之相同。
set -euo pipefail
cd "$(dirname "$0")/.."
out=.build/window-frame-probe
mkdir -p "$out"
swiftc -O tests/native-tabs-probe/TabsFixture.swift -o "$out/fixture"
cp tests/window-frame-probe/FrozenAppProbe.swift "$out/main.swift"   # 多文件编译时顶层代码要在 main.swift 里
swiftc -O prototype/Core/WindowFrameResolver.swift "$out/main.swift" -o "$out/probe"
"$out/fixture" & fixture=$!
trap 'kill -CONT $fixture 2>/dev/null || true; kill $fixture 2>/dev/null || true' EXIT
perl -e 'select(undef,undef,undef,3)'
line=$("$out/probe" "$fixture" | grep -v '^SKIP' | head -1)
[ -n "$line" ] || { echo "SKIP window-frame: 夹具没有窗口或没有辅助功能权限"; exit 0; }
kill -STOP "$fixture"
"$out/probe" "$fixture" $line
