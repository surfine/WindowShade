#!/bin/bash
# AirPods 转头交叉核对：纯逻辑，不碰 CoreMotion、Vision。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/head-motion-crosscheck-tests
swiftc -module-cache-path .build/head-motion-crosscheck-tests/cache -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/HeadMotionCrossCheck.swift \
  tests/HeadMotionCrossCheckTests.swift -o .build/head-motion-crosscheck-tests/run
.build/head-motion-crosscheck-tests/run
