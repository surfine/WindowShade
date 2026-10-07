#!/bin/bash
# PERF-11（完整）：效能资格的逐项判定。
# 纯逻辑测试，不需要屏幕录制权限，也不碰真机功耗（那份见 RUNBOOK.md 的 not_run 段）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/perf-qualification-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Effects/PerfQualification.swift \
  tests/PerfQualificationTests.swift \
  -o .build/perf-qualification-tests/perf-qualification
.build/perf-qualification-tests/perf-qualification
