#!/bin/bash
# 实时活动 → 岛的六态（C03）：13 个种类不重不漏，各落在 thinking／response／transient／hidden。
# 用法：bash tests/run-notch-activity-motion-tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/notch-activity-motion-tests"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" "$ROOT/prototype/App/Motion.swift" "$ROOT/prototype/Core/FlickMotion.swift" "$ROOT/prototype/Core/NotchLevelEars.swift" "$ROOT/prototype/Core/NotchLevelStep.swift" "$ROOT/prototype/Core/NotchLevelGate.swift" "$ROOT/prototype/Core/NotchLevelSuppression.swift" \
  "$ROOT/prototype/Core/IslandMotionState.swift" "$ROOT/prototype/Core/WireJSON.swift" "$ROOT/prototype/Core/UsageReading.swift" "$ROOT/prototype/Core/NotchActivities.swift" "$ROOT/prototype/Core/NotchActivityMotion.swift" "$ROOT/prototype/Core/ReleaseDefaults.swift" "$ROOT/prototype/Core/GlanceIntent.swift" \
  "$ROOT/prototype/Core/IslandMetrics.swift" "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/FocusTimer.swift" \
  "$ROOT/tests/support/MotionTestSupport.swift" "$ROOT/tests/NotchActivityMotionTests.swift" \
  -o "$BUILD/notch-activity-motion-tests"
"$BUILD/notch-activity-motion-tests"
