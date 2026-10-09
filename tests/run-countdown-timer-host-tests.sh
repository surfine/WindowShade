#!/usr/bin/env bash
# TMR-2：计时器宿主（文字、选分钟、到点只响一次、静音不响、超时结束、唤醒节奏、设置）。纯逻辑，不开窗口、不出声。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/countdown-timer-host"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/CountdownTimer.swift" "$ROOT/prototype/App/CountdownTimerHost.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/CountdownTimerHostTests.swift" -o "$BUILD/countdown-timer-host-tests"
"$BUILD/countdown-timer-host-tests"
