#!/bin/bash
# 指挥模式手势识别纯逻辑：声调、拍子、拒识（交接 v3 CONDUCTOR-ACCEPTANCE C-011…C-022 的纯逻辑部分）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/conductor-gesture-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/ConductorGesture.swift tests/ConductorGestureTests.swift \
  -o .build/conductor-gesture-tests/conductor
.build/conductor-gesture-tests/conductor
