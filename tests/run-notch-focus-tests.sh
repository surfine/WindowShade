#!/bin/bash
# M07：刘海那一排的焦点导航（默认焦点、不绕回、读屏字符串、指针进入时焦点隐藏、按键对应、样式数值）。纯 Foundation。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-focus-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  prototype/Core/Contracts.swift prototype/Core/FocusNavigator.swift prototype/Core/NotchSentence.swift \
  prototype/Core/NotchRow.swift prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift \
  prototype/App/NotchFocusController.swift tests/support/WS2TestSupport.swift tests/NotchFocusTests.swift \
  -o .build/notch-focus-tests/tests
.build/notch-focus-tests/tests
