#!/bin/bash
# PERF-01：诊断器的开关、时限、抓栈策略与卡顿判定。
# 纯逻辑 + 进程内可观察状态；真机线程与功耗数字不在这一层（RUNBOOK.md 的 not_run 段）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/diagnostics-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Support/SecureLogFile.swift \
  prototype/Support/Diagnostics.swift \
  tests/DiagnosticsTests.swift \
  -framework Cocoa -o .build/diagnostics-tests/diagnostics
.build/diagnostics-tests/diagnostics
