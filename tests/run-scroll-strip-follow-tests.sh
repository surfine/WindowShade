#!/bin/bash
# 卷轴第二批（SS-05 张开跟手的概览、SS-06 滑完的焦点和按 App 记住宽度、SS-07 标题栏拖到两列之间）：纯逻辑，不操作任何窗口。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/scroll-strip-follow-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/ScrollStrip.swift prototype/Core/StripWidthMemory.swift prototype/Core/MagicTiling.swift \
  prototype/Core/ArrangeGap.swift prototype/Core/FlickMotion.swift tests/ScrollStripFollowTests.swift \
  -o .build/scroll-strip-follow-tests/run
.build/scroll-strip-follow-tests/run
