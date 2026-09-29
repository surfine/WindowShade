#!/bin/bash
# Rectangle 键位、方向键换成字母（Swish 的键位）与“放大一点 / 缩小一点 / 居中”的算法（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/rectangle-keymap-tests
swiftc -parse-as-library prototype/Core/RectangleKeymap.swift prototype/Core/DirectionKeys.swift prototype/Core/ResizeStep.swift tests/RectangleKeymapTests.swift -o .build/rectangle-keymap-tests/keymap
.build/rectangle-keymap-tests/keymap
