#!/bin/bash
# F10：置顶镜像流锁屏/熄屏自动暂停的状态机（纯逻辑，不需要图形会话）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/pinned-suspend-tests
swiftc -parse-as-library -O -swift-version 6 \
  prototype/Support/PinnedStreamPauseGate.swift \
  tests/PinnedPreviewSuspendTests.swift \
  -o .build/pinned-suspend-tests/tests
.build/pinned-suspend-tests/tests
