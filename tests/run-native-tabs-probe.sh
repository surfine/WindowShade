#!/bin/bash
# 规格 R4 前提核对（手动跑，要辅助功能权限，会在屏幕上闪一下两扇窗口约 10 秒）：
# 起一个夹具 App，三扇窗口并成原生标签页、外加一扇独立窗口，再从外面读它的 AXWindows。
set -euo pipefail
cd "$(dirname "$0")/.."
out=.build/native-tabs-probe
mkdir -p "$out"
swiftc -O tests/native-tabs-probe/TabsFixture.swift -o "$out/fixture"
swiftc -O tests/native-tabs-probe/AXWindowsProbe.swift -o "$out/probe"
"$out/fixture" & fixture=$!
trap 'kill $fixture 2>/dev/null || true' EXIT
perl -e 'select(undef,undef,undef,3)'   # 等夹具的窗口排好
"$out/probe" "$fixture"
