#!/usr/bin/env bash
# CAL-2：日程来源（没授权不建 store、改动时重查、一次性定时器只挂下一个时刻）。用假的 store，不需要日历权限。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/calendar-source-tests"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/CalendarActivity.swift" "$ROOT/prototype/App/CalendarSource.swift" \
  "$ROOT/tests/CalendarSourceTests.swift" -o "$BUILD/tests"
"$BUILD/tests"
