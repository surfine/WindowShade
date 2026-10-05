#!/bin/bash
# 锁屏开合效果的生命周期与锁态解析（unknown 一律当锁着）。这份测试此前没有 runner，从没被编译过。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/lock-overlay-lifecycle-tests
swiftc -parse-as-library prototype/Core/SessionLockState.swift prototype/Core/LockOverlayLifecycle.swift \
  prototype/Core/FlickMotion.swift prototype/Effects/FoldDriver.swift tests/LockOverlayLifecycleTests.swift \
  -o .build/lock-overlay-lifecycle-tests/lifecycle
.build/lock-overlay-lifecycle-tests/lifecycle
