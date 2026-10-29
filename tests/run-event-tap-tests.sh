#!/bin/bash
# PERF-03：双击/三击「吞不吞」的原子状态机（有界等待、迟到不折叠、begin/abandon 互斥）。
# 增补第 15 步：标题栏双击在后台判定（TitlebarTapRoute），主线程卡 600 ms 时不漏给系统。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/event-tap-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/App/TapDecision.swift \
  prototype/App/TitlebarTapRoute.swift \
  tests/EventTapDecisionTests.swift \
  -o .build/event-tap-tests/event-tap
.build/event-tap-tests/event-tap
