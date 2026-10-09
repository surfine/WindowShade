#!/usr/bin/env bash
# CAL-1：日程纯逻辑（选哪个、阶段、会议链接、下一个时刻）。不碰 EventKit，不需要图形会话。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/calendar-activity-tests"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/CalendarActivity.swift" "$ROOT/tests/CalendarActivityTests.swift" \
  -o "$BUILD/tests"
"$BUILD/tests"
