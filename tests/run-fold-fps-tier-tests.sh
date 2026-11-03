#!/bin/bash
# PERF-13：窗口折叠会话采集帧率分档（纯逻辑，不需要屏幕录制权限）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/fold-fps-tier-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Effects/WindowFoldFPS.swift \
  tests/WindowFoldFPSTests.swift \
  -o .build/fold-fps-tier-tests/fps-tier
.build/fold-fps-tier-tests/fps-tier
