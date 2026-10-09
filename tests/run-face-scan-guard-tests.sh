#!/bin/bash
# 刷脸扫描守卫纯逻辑（实验，只产出证据，不接系统解锁）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-scan-guard-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/SessionLockState.swift prototype/Core/FaceScanGuard.swift \
  prototype/Core/FaceTemplateSet.swift tests/FaceScanGuardTests.swift -o .build/face-scan-guard-tests/guard
.build/face-scan-guard-tests/guard
