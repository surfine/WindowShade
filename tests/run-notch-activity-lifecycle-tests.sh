#!/bin/bash
# LA56：实时活动统一的样子与生命周期（《实时活动晋级》三）。排序键、1.5 秒门槛、过期沉底、结束留 4 秒与那一排留到看过、
# 两件同时在的耳朵分配、文件架不占位、各来源的过期与收场方式。纯 Foundation，不碰 AppKit 与真机。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-activity-lifecycle-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/NotchActivities.swift prototype/Core/NotchSentence.swift prototype/Core/NotchRow.swift \
  tests/NotchActivityLifecycleTests.swift \
  -o .build/notch-activity-lifecycle-tests/tests
.build/notch-activity-lifecycle-tests/tests
