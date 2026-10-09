#!/usr/bin/env bash
# 刘海里的助手审批卡（M01）：风险→按钮、真回执、同层排队，以及认证那一行的文案。纯逻辑，不起界面、不调 Touch ID。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/approval-card"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/AgentSessions.swift" \
  "$ROOT/prototype/Core/AuthorizationModels.swift" "$ROOT/prototype/App/AuthorizationCopy.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/ApprovalCardTests.swift" \
  -o "$BUILD/approval-card-tests"
"$BUILD/approval-card-tests"
