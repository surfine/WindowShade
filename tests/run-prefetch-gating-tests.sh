#!/bin/bash
# F03：预热门控真值表、双击准入快照有效期、预过滤计数（不需要图形会话）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/prefetch-gating-tests
swiftc -swift-version 6 -parse-as-library \
  prototype/Window/WindowListCache.swift \
  prototype/Window/TitlebarPrefetchGate.swift \
  tests/PrefetchGatingTests.swift \
  -o .build/prefetch-gating-tests/tests
.build/prefetch-gating-tests/tests
