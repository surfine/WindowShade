#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/countdown-timer"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/CountdownTimer.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/CountdownTimerTests.swift" -o "$BUILD/countdown-timer-tests"
"$BUILD/countdown-timer-tests"
