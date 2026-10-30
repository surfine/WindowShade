#!/usr/bin/env bash
# 编程会话审批卡的尺寸、摆法、琥珀点缩放与弹簧令牌选择。纯逻辑，不起界面。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/session-card-style"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/AgentSessions.swift" "$ROOT/prototype/Core/SessionCardStyle.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/SessionCardStyleTests.swift" \
  -o "$BUILD/tests"
"$BUILD/tests"
