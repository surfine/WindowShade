#!/bin/bash
# 卷轴的看一眼与概览（纯逻辑，不操作任何窗口）。卷轴的停靠、滑动、列宽、增减在 run-magic-tiling-tests.sh 里。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/scroll-strip-tests
swiftc -parse-as-library prototype/Core/ScrollStrip.swift prototype/Core/MagicTiling.swift prototype/Core/ArrangeGap.swift \
  prototype/Core/FlickMotion.swift tests/ScrollStripTests.swift -o .build/scroll-strip-tests/strip
.build/scroll-strip-tests/strip
