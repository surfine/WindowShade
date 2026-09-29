#!/bin/bash
# 窗口之间每条缝的认对、拖动、松手落点（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/seam-layout-tests
swiftc -parse-as-library prototype/Core/SeamLayout.swift prototype/Core/SplitPair.swift prototype/Core/ArrangeGap.swift prototype/Core/FlickMotion.swift \
  tests/SeamLayoutTests.swift -o .build/seam-layout-tests/seams
.build/seam-layout-tests/seams
