#!/bin/bash
# 屏幕形状：连续曲率角、bezelPath 的校验、机型表与换算、岛贴合硬件的规则（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/display-shape-tests
swiftc -O -parse-as-library prototype/Core/DisplayShape.swift tests/DisplayShapeTests.swift -o .build/display-shape-tests/shape
.build/display-shape-tests/shape
