#!/bin/bash
# 系统灵動岛：能力映射真值表 + 本机 MobileGestalt 真实读数（纯逻辑）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/system-island-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library -O \
  prototype/Core/SystemIsland.swift tests/SystemIslandTests.swift -o .build/system-island-tests/system-island
.build/system-island-tests/system-island
