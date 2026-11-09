#!/bin/bash
# 岛的六态模型（C02）：27.3 #islandSizing 的 tag 0–5、形状 adapter、状态→弹簧。
# 用法：bash tests/run-island-motion-state-tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/island-motion-state-tests"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" "$ROOT/prototype/App/Motion.swift" "$ROOT/prototype/Core/FlickMotion.swift" "$ROOT/prototype/Core/NotchLevelEars.swift" "$ROOT/prototype/Core/NotchLevelStep.swift" "$ROOT/prototype/Core/NotchLevelGate.swift" "$ROOT/prototype/Core/NotchLevelSuppression.swift" \
  "$ROOT/prototype/Core/IslandMotionState.swift" "$ROOT/prototype/Core/WireJSON.swift" "$ROOT/prototype/Core/UsageReading.swift" "$ROOT/prototype/Core/NotchActivities.swift" "$ROOT/prototype/Core/ReleaseDefaults.swift" "$ROOT/prototype/Core/GlanceIntent.swift" \
  "$ROOT/prototype/Core/IslandMetrics.swift" "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/FocusTimer.swift" \
  "$ROOT/tests/support/MotionTestSupport.swift" "$ROOT/tests/IslandMotionStateTests.swift" \
  -o "$BUILD/island-motion-state-tests"
"$BUILD/island-motion-state-tests"
