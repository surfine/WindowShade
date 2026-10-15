#!/bin/bash
# SS-04：卷轴概览与刘海互通。落点判定、放行时不出落点、收进刘海后卷轴补位、放回的位置、
# 停在屏幕外的列进刘海那一排左段。纯 Foundation / CoreGraphics，不碰 AppKit 与真窗口。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/strip-notch-exchange-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  prototype/Core/ScrollStrip.swift prototype/Core/MagicTiling.swift prototype/Core/ArrangeGap.swift \
  prototype/Core/FlickMotion.swift prototype/Core/StripNotchExchange.swift \
  prototype/Core/Contracts.swift prototype/Core/FocusNavigator.swift prototype/Core/NotchSentence.swift \
  prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift prototype/Core/NotchRow.swift prototype/Core/InteractionCoordinator.swift \
  tests/StripNotchExchangeTests.swift \
  -o .build/strip-notch-exchange-tests/tests
.build/strip-notch-exchange-tests/tests
