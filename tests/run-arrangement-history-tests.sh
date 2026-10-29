#!/bin/bash
# 排布历史（纯逻辑）：收起 -> 收进刘海 -> 左半屏三次撤销依次回去；手动挪过的窗口不再被错撤。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/arrangement-history-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/ArrangementHistory.swift tests/ArrangementHistoryTests.swift \
  -o .build/arrangement-history-tests/run
.build/arrangement-history-tests/run
