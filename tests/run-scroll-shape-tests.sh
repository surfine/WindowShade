#!/bin/bash
# 滚动事件的来源分类（触控板／普通滚轮／平滑滚轮）：纯逻辑，不发事件、不碰窗口。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/scroll-shape-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/ScrollShape.swift tests/ScrollShapeTests.swift -o .build/scroll-shape-tests/tests
.build/scroll-shape-tests/tests
