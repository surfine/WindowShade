#!/bin/bash
# 岛的量法：常量与推导关系（纯逻辑）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/island-metrics-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library -O \
  prototype/Core/IslandMetrics.swift tests/IslandMetricsTests.swift -o .build/island-metrics-tests/island-metrics
.build/island-metrics-tests/island-metrics
