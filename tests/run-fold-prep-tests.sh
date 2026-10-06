#!/bin/bash
# PERF-05：图像准备（vImage 换色彩空间 + 建纹理）移出主线程的配套策略：
# 代际换入与有界缓存。纯逻辑，不依赖 AppKit／Metal。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/fold-prep-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Effects/FoldImagePrep.swift \
  tests/FoldPrepTests.swift \
  -o .build/fold-prep-tests/fold-prep
.build/fold-prep-tests/fold-prep
