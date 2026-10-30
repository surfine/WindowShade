#!/usr/bin/env bash
# 照系统的岛（AARON-DECISIONS-2026-10-29 第 28 至 33 条）：暂定尺寸只在 IslandMetrics 一处，
# 点耳朵／点本体的分块、长按去哪、空格与 Return、悬停不展开。纯 Foundation，不碰 AppKit 与真机。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/notch-island-metrics"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" \
  "$ROOT/prototype/Core/WireJSON.swift" "$ROOT/prototype/Core/UsageReading.swift" "$ROOT/prototype/Core/ReleaseDefaults.swift" \
  "$ROOT/prototype/Core/NotchActivities.swift" "$ROOT/prototype/Core/NotchRoomPolicy.swift" "$ROOT/prototype/Core/NotchRow.swift" \
  "$ROOT/prototype/Core/FocusNavigator.swift" "$ROOT/prototype/Core/NotchSentence.swift" "$ROOT/prototype/Core/InteractionCoordinator.swift" \
  "$ROOT/prototype/Core/IslandMetrics.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/NotchIslandMetricsTests.swift" -o "$BUILD/notch-island-metrics-tests"
"$BUILD/notch-island-metrics-tests"
