#!/bin/bash
# LA-7：在刘海那一排里打字筛选（匹配含拼音首字母、悬停打开不接键盘、Esc 两步、没有匹配的）。纯 Foundation。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-filter-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  prototype/Core/Contracts.swift prototype/Core/FocusNavigator.swift prototype/Core/NotchSentence.swift \
  prototype/Core/NotchRow.swift prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift \
  prototype/App/NotchFocusController.swift tests/support/WS2TestSupport.swift tests/NotchRowFilterTests.swift \
  -o .build/notch-filter-tests/tests
.build/notch-filter-tests/tests
