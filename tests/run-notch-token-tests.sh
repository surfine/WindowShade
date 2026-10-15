#!/bin/bash
# 刘海动效与紧凑令牌对齐（C01）：形状 → 弹簧、内容时序、停留时长、两耳文字、信息点几何。
# 用法：bash tests/run-notch-token-tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/notch-token-tests"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" "$ROOT/prototype/App/Motion.swift" "$ROOT/prototype/Core/FlickMotion.swift" "$ROOT/prototype/Core/NotchLevelEars.swift" "$ROOT/prototype/Core/NotchLevelStep.swift" "$ROOT/prototype/Core/NotchLevelGate.swift" "$ROOT/prototype/Core/NotchLevelSuppression.swift" \
  "$ROOT/prototype/Core/WireJSON.swift" "$ROOT/prototype/Core/UsageReading.swift" "$ROOT/prototype/Core/NotchActivities.swift" "$ROOT/prototype/Core/ReleaseDefaults.swift" "$ROOT/prototype/Core/GlanceIntent.swift" \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/FocusTimer.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/NotchTokenTests.swift" \
  -o "$BUILD/notch-token-tests"
"$BUILD/notch-token-tests"
