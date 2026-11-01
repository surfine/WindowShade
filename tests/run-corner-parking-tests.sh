#!/bin/bash
# 角落停放：几何、避开别的屏、8×8 可见判定。纯 CoreGraphics，不依赖 AppKit。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/corner-parking-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Core/CornerParking.swift \
  tests/CornerParkingTests.swift \
  -o .build/corner-parking-tests/tests
.build/corner-parking-tests/tests
