#!/bin/bash
# PERF-03：双击/三击「吞不吞」的原子状态机（有界等待、迟到不折叠、begin/abandon 互斥）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/event-tap-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/App/TapDecision.swift \
  tests/EventTapDecisionTests.swift \
  -o .build/event-tap-tests/event-tap
.build/event-tap-tests/event-tap
