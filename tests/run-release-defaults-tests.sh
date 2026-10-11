#!/bin/bash
# 1.0.16 默认值总账（纯逻辑）：1.0.15 的键不动，新键没验过一律关。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/release-defaults-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/ReleaseDefaults.swift prototype/Core/NotchLevelSetting.swift prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift \
  prototype/Core/NotchRow.swift prototype/Core/NotchSentence.swift prototype/Core/Contracts.swift prototype/Core/DockClickGuard.swift prototype/Core/SwitcherOrigin.swift \
  tests/ReleaseDefaultsTests.swift -o .build/release-defaults-tests/tests
.build/release-defaults-tests/tests
