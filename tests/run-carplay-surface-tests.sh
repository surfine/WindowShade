#!/bin/bash
# CarPlay 全屏的纯映射：会话状态 -> 画什么、写什么（合成模式，无传输、无凭据）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/carplay-tests
swiftc -swift-version 6 -module-cache-path "$PWD/.build/module-cache" \
  prototype/Core/WS2CarPlaySession.swift prototype/Core/WS2CarPlaySurfaceModel.swift \
  tests/WS2CarPlaySurfaceModelTests.swift -o .build/carplay-tests/surface-model
.build/carplay-tests/surface-model
