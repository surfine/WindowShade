#!/bin/bash
# 卸载扫描计划（Core 纯模型，内存假文件系统，全离线）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/uninstall-tests
swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path "$PWD/.build/module-cache" \
  prototype/Core/WS2AppUninstallPlan.swift tests/WS2AppUninstallPlanTests.swift \
  -o .build/uninstall-tests/uninstall-plan
.build/uninstall-tests/uninstall-plan
