#!/bin/bash
# 跨桌面移动：只测“符号/类找不到就回退”的路径，不移动真实窗口。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/bridged-space-move-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Support/SkyLightFramework.swift \
  prototype/Private/BridgedSpaceMove.swift \
  tests/BridgedSpaceMoveTests.swift \
  -framework Cocoa \
  -o .build/bridged-space-move-tests/tests
.build/bridged-space-move-tests/tests
