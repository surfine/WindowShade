#!/bin/bash
# 标题栏手势：识别状态机（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/gesture-tests
swiftc prototype/Core/TrackpadGesture.swift tests/TrackpadGestureTests.swift -o .build/gesture-tests/recognizer
.build/gesture-tests/recognizer
