#!/bin/bash
# F01：分屏把手调度（签名跳过、暂停/恢复、拖动中不刷新）的纯逻辑测试，不需要图形会话。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/splitview-scheduling-tests
swiftc -parse-as-library -O \
  prototype/Core/FlickMotion.swift \
  prototype/Core/SplitPair.swift \
  prototype/Core/SplitScan.swift \
  tests/SplitViewSchedulingTests.swift \
  -o .build/splitview-scheduling-tests/tests
.build/splitview-scheduling-tests/tests
