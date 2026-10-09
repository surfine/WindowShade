#!/bin/bash
# 刘海让开原生全屏 / 调度中心：真值表、桌面类型解析、几何只平移（纯逻辑）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-space-gate-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library -O \
  prototype/App/NotchSpaceGate.swift tests/NotchSpaceGateTests.swift -o .build/notch-space-gate-tests/gate
.build/notch-space-gate-tests/gate
