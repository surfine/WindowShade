#!/bin/bash
# M11：窗口和会话合成一排。分段与坐标（各种数量组合）、格子编号、右段放什么、读屏句子、焦点跨过竖线、
# 主人合并（notchShelf / agentSessions）以后的租约行为。纯 Foundation，不碰 AppKit 与真机。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-row-merge-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift \
  prototype/Core/Contracts.swift prototype/Core/FocusNavigator.swift prototype/Core/NotchSentence.swift \
  prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift prototype/Core/NotchRow.swift prototype/Core/InteractionCoordinator.swift \
  prototype/App/NotchFocusController.swift tests/support/WS2TestSupport.swift tests/NotchRowMergeTests.swift \
  -o .build/notch-row-merge-tests/tests
.build/notch-row-merge-tests/tests
