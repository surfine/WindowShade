#!/usr/bin/env bash
# 刘海先量空位（LA-1 / LA-2 / LA-3）：纯规则测试，不碰系统。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/notch-room-policy"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/NotchRoomPolicy.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/NotchRoomPolicyTests.swift" -o "$BUILD/notch-room-policy-tests"
"$BUILD/notch-room-policy-tests"
