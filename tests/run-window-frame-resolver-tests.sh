#!/bin/bash
# 规格 R7：取窗口外框的四级回退判据。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/window-frame-resolver-tests
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WindowFrameResolver.swift tests/WindowFrameResolverTests.swift \
  -o .build/window-frame-resolver-tests/run
.build/window-frame-resolver-tests/run
