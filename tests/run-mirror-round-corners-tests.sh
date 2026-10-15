#!/bin/bash
# 规格 H1：mirrorRoundCorners 提速版与旧实现逐字节相同，并打印 4K 一张的前后耗时。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/mirror-round-corners-tests
swiftc -O -swift-version 6 -parse-as-library \
  prototype/Capture/PreviewRenderer.swift tests/PreviewRendererStubs.swift tests/MirrorRoundCornersTests.swift \
  -o .build/mirror-round-corners-tests/run
.build/mirror-round-corners-tests/run
