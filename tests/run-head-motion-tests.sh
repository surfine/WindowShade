#!/bin/bash
# 耳机头动胶水：度数、按屏基线、换耳机重新校准。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/head-motion-tests
swiftc -module-cache-path .build/head-motion-tests/cache -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/WS2HeadGesture.swift prototype/Core/WS2HeadMotionFeed.swift \
  tests/HeadMotionFeedTests.swift -o .build/head-motion-tests/run
.build/head-motion-tests/run
