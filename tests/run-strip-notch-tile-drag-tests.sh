#!/bin/bash
# SS-04：刘海那一排左段收着的一格拖出来放回卷轴，“按下、拖、松手”的判定。纯 Foundation / CoreGraphics。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/strip-notch-tile-drag-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/StripNotchTileDrag.swift prototype/Core/NotchRow.swift \
  prototype/Core/Contracts.swift prototype/Core/FocusNavigator.swift prototype/Core/NotchSentence.swift \
  prototype/Core/NotchActivities.swift prototype/Core/InteractionCoordinator.swift \
  tests/StripNotchTileDragTests.swift \
  -o .build/strip-notch-tile-drag-tests/tests
.build/strip-notch-tile-drag-tests/tests
