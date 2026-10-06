#!/bin/bash
# PERF-06：page 金字塔的重建键（静态源一张只建一次、源/采样/格式/尺寸变更各重建一次）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/fold-page-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Effects/FoldPageKey.swift \
  tests/FoldPageKeyTests.swift \
  -o .build/fold-page-tests/fold-page
.build/fold-page-tests/fold-page
