#!/bin/bash
# 录屏胶囊清理：真实样本 + 合成标题栏，纯像素计算，不需要任何权限。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/capture-indicator-tests
swiftc prototype/Capture/CaptureIndicatorRemoval.swift tests/CaptureIndicatorTests.swift \
  -framework AppKit -o .build/capture-indicator-tests/run
.build/capture-indicator-tests/run
