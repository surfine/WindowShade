#!/usr/bin/env bash
# 刘海岛的纯几何：外接屏胶囊不顶出屏幕、弹簧飞行保护。纯 CoreGraphics，不碰 AppKit。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/notch-island-geometry"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/NotchIslandGeometry.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/NotchIslandGeometryTests.swift" -o "$BUILD/notch-island-geometry-tests"
"$BUILD/notch-island-geometry-tests"
