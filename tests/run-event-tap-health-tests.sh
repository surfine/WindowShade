#!/bin/bash
# 规格 R1／R3：事件 tap 登记表只重开主人想要开着的 tap；睡醒三档的时间表。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/event-tap-health-tests
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/EventTapHealth.swift prototype/Support/SendableSystemHandles.swift tests/EventTapHealthTests.swift \
  -o .build/event-tap-health-tests/run
.build/event-tap-health-tests/run
