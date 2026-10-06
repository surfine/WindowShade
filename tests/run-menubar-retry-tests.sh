#!/bin/bash
# PERF-09：菜单栏空位量不到时的重试预算（纯 Foundation，无 UI、无辅助功能、无图形会话）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/menubar-retry-tests
swiftc -parse-as-library -O \
  prototype/App/MenuBarCoverRetry.swift \
  tests/MenuBarRetryTests.swift \
  -o .build/menubar-retry-tests/tests
.build/menubar-retry-tests/tests
