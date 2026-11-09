#!/bin/bash
# 岛形变接力与弹簧装配（C04/C05）：MorphRetarget 的实时速度／归一化初速度／kick，
# 以及 Motion.spring 的 keyPath 与 settlingDuration。
# 用法：bash tests/run-island-transition-tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/island-transition-tests"
mkdir -p "$BUILD"

"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/FlickMotion.swift" \
  "$ROOT/tests/support/MotionTestSupport.swift" "$ROOT/tests/MorphRetargetTests.swift" \
  -o "$BUILD/morph-retarget-tests"
"$BUILD/morph-retarget-tests"

"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" \
  "$ROOT/prototype/App/Motion.swift" "$ROOT/prototype/Core/FlickMotion.swift" \
  "$ROOT/prototype/Core/NotchLevelEars.swift" "$ROOT/prototype/Core/NotchLevelStep.swift" \
  "$ROOT/prototype/Core/NotchLevelGate.swift" "$ROOT/prototype/Core/NotchLevelSuppression.swift" \
  "$ROOT/prototype/Core/IslandMotionState.swift" "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/tests/support/MotionTestSupport.swift" "$ROOT/tests/MotionSpringTests.swift" \
  -o "$BUILD/motion-spring-tests"
"$BUILD/motion-spring-tests"
