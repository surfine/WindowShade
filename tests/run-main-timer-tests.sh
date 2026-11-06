#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/main-timer-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Support/MainTimer.swift tests/MainTimerTests.swift \
  -framework AppKit -o .build/main-timer-tests/tests
.build/main-timer-tests/tests
