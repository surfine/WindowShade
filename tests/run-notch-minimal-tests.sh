#!/bin/bash
# M13：最小呈现（开关 Notch.minimalPresentation，默认关）。开关关着时的布局决策快照、开着时最小形的选择与几何、
# 互换、提醒撞上播放时的走法、读屏标签、进度弧。纯 Foundation，不碰 AppKit 与真机。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-minimal-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift prototype/Core/FlickMotion.swift \
  tests/NotchMinimalTests.swift \
  -o .build/notch-minimal-tests/tests
.build/notch-minimal-tests/tests
