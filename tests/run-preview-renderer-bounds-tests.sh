#!/bin/bash
# 规格 R47：像素函数在极端图像上不越界（越界会直接崩，崩了就是失败）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/preview-renderer-bounds-tests
swiftc -O -swift-version 6 -parse-as-library \
  prototype/Capture/PreviewRenderer.swift tests/PreviewRendererStubs.swift tests/PreviewRendererBoundsTests.swift \
  -o .build/preview-renderer-bounds-tests/run
.build/preview-renderer-bounds-tests/run
