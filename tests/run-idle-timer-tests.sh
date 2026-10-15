#!/bin/bash
# F06：空闲定时器规则（纯逻辑）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/idle-timer-tests
swiftc -parse-as-library -O -swift-version 6 \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  prototype/Core/SessionLockState.swift \
  prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift \
  prototype/Core/IdleTimerPolicy.swift \
  tests/IdleTimerTests.swift \
  -o .build/idle-timer-tests/tests
.build/idle-timer-tests/tests
