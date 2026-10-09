#!/bin/bash
# R02：无刘海屏胶囊五态的尺寸表、中心锚点、开关两种位置（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/capsule-shape-tests
swiftc -O -parse-as-library prototype/Core/DisplayShape.swift tests/CapsuleShapeTests.swift -o .build/capsule-shape-tests/shape
.build/capsule-shape-tests/shape
