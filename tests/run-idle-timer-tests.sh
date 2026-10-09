#!/bin/bash
# F06：空闲定时器规则（纯逻辑）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/idle-timer-tests
swiftc -parse-as-library -O -swift-version 6 \
  prototype/Core/SessionLockState.swift \
  prototype/Core/NotchActivities.swift \
  prototype/Core/IdleTimerPolicy.swift \
  tests/IdleTimerTests.swift \
  -o .build/idle-timer-tests/tests
.build/idle-timer-tests/tests
