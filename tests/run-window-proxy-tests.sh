#!/bin/bash
# 第 13–14 步：代理先动、真窗后到的纯计算（跟手插值、改道连续、只写一次的账、减少动态效果、收起动画默认开）。
# 用法：bash tests/run-window-proxy-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/window-proxy-tests
swiftc -parse-as-library prototype/Core/FlickMotion.swift prototype/Core/WindowProxyMotion.swift tests/WindowProxyMotionTests.swift \
  -o .build/window-proxy-tests/proxy
.build/window-proxy-tests/proxy
