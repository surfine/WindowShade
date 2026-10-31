#!/usr/bin/env bash
# 防误触的几条纯规则（上推门槛、落点停留、冷却反向豁免、审批卡新鲜按下、晃一晃只认横向）。纯逻辑。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/guard-rules"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -parse-as-library \
  "$ROOT/prototype/Core/GuardRules.swift" "$ROOT/prototype/Core/ApprovalFreshness.swift" "$ROOT/prototype/Core/WindowShake.swift" \
  "$ROOT/prototype/Core/TrackpadGesture.swift" "$ROOT/prototype/Core/ArrangeGap.swift" "$ROOT/prototype/Core/DisplayRefit.swift" "$ROOT/prototype/Core/NotchAlerts.swift" "$ROOT/prototype/Core/FlickMotion.swift" "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/SessionCardStyle.swift" "$ROOT/prototype/Core/AgentSessions.swift" "$ROOT/prototype/Core/IslandMetrics.swift" \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" \
  "$ROOT/tests/GuardRulesTests.swift" -o "$BUILD/guard-rules-tests"
"$BUILD/guard-rules-tests"
