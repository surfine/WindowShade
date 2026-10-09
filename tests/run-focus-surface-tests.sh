#!/usr/bin/env bash
# 番茄钟刘海表面（M10）：提醒文案与停留、呼吸规则、休息回来监听。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/focus-surface"
mkdir -p "$BUILD"
SWIFTC_BIN="${SWIFTC:-swiftc}"
FLAGS=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library)
# 纯逻辑：计时器 + 提醒 + 呼吸规则。
"$SWIFTC_BIN" "${FLAGS[@]}" "$ROOT/prototype/Core/Contracts.swift" "$ROOT/tests/support/WS2TestSupport.swift" \
  "$ROOT/prototype/Core/FocusTimer.swift" "$ROOT/tests/FocusTimerTests.swift" -o "$BUILD/focus-timer-reminders"
"$BUILD/focus-timer-reminders"
# 休息回来监听（AppKit，监听用假的装卸）。
"$SWIFTC_BIN" "${FLAGS[@]}" "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/App/FocusRestReturnMonitor.swift" "$ROOT/tests/FocusSurfaceTests.swift" -o "$BUILD/focus-surface"
"$BUILD/focus-surface"
