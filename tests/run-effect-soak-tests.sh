#!/bin/bash
# PERF-11（最小）：冒烟脚本的阶段覆盖、截断与跳段校验。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/effect-soak-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Effects/EffectSoakScript.swift \
  tests/EffectSoakTests.swift \
  -o .build/effect-soak-tests/effect-soak
.build/effect-soak-tests/effect-soak
