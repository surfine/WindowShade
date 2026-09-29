#!/bin/bash
# 魔法平铺的规划、晃一晃的识别（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/magic-tiling-tests
swiftc -parse-as-library prototype/Core/MagicTiling.swift prototype/Core/ScrollStrip.swift prototype/Core/WindowShake.swift prototype/Core/ArrangeGap.swift prototype/Core/DockLockRule.swift prototype/Core/GestureCoach.swift prototype/Core/FlickMotion.swift \
  tests/MagicTilingTests.swift -o .build/magic-tiling-tests/magic
.build/magic-tiling-tests/magic
