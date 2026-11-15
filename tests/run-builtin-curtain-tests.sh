#!/usr/bin/env bash
# 指针离开内屏就遮住：遮不遮的纯规则测试，不碰屏幕。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/builtin-curtain"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/BuiltInCurtainPolicy.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/BuiltInCurtainPolicyTests.swift" -o "$BUILD/builtin-curtain-tests"
"$BUILD/builtin-curtain-tests"
