#!/bin/bash
# 分屏（Split View）的认对、拖中间那条、松手落点（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/split-pair-tests
swiftc -parse-as-library prototype/Core/SplitPair.swift prototype/Core/ArrangeGap.swift prototype/Core/FlickMotion.swift \
  tests/SplitPairTests.swift -o .build/split-pair-tests/split
.build/split-pair-tests/split
