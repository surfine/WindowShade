#!/bin/bash
# ActivityKit 让位策略（C06）：默认 inAppOnly；yieldToSystem 只在系统岛 + ActivityKit 都在时让位。
# 用法：bash tests/run-activitykit-bridge-tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/activitykit-bridge-tests"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/SystemIsland.swift" "$ROOT/prototype/Core/ActivityKitBridge.swift" \
  "$ROOT/tests/support/MotionTestSupport.swift" "$ROOT/tests/ActivityKitBridgeTests.swift" \
  -o "$BUILD/activitykit-bridge-tests"
"$BUILD/activitykit-bridge-tests"
