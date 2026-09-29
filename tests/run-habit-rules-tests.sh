#!/bin/bash
# 卡住时刘海开口的规则表与判定（纯逻辑，不听按键、不碰用户的设置）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/habit-rules-tests
swiftc -parse-as-library prototype/Core/SwitcherOrigin.swift prototype/Core/GestureCoach.swift \
  prototype/Core/HabitRules.swift tests/HabitRulesTests.swift -o .build/habit-rules-tests/habits
.build/habit-rules-tests/habits
