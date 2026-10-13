#!/usr/bin/env bash
# CAL-3、CAL-4：日程的画面与授权的纯逻辑（阶段→画法、只鼓一次、共享时无标题、授权拒绝后无界面、加入交给谁）。
# 不碰 EventKit、AppKit，不需要图形会话。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/calendar-presentation-tests"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/CalendarActivity.swift" "$ROOT/prototype/Core/CalendarPresentation.swift" \
  "$ROOT/tests/CalendarPresentationTests.swift" -o "$BUILD/tests"
"$BUILD/tests"
