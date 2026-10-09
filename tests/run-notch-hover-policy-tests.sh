#!/usr/bin/env bash
# 悬停不误触（LA-4）：纯规则测试，不碰系统。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/notch-hover-policy"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/NotchHoverPolicy.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/NotchHoverPolicyTests.swift" -o "$BUILD/notch-hover-policy-tests"
"$BUILD/notch-hover-policy-tests"
