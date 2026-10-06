#!/bin/bash
# PERF-02：预览/PiP 输出尺寸纯函数（上限、优先级、浮点 scale、异常输入）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/capture-sizing-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Capture/CaptureOutputSizing.swift \
  tests/ScreenCaptureSizingTests.swift \
  -framework CoreGraphics -o .build/capture-sizing-tests/sizing
.build/capture-sizing-tests/sizing
