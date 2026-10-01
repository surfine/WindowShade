#!/bin/bash
# 应用真实的 LidAngleSource：能拿到读数，且走「订阅推送 + 1Hz 看门狗」而不是 4Hz 轮询。
# 不需要图形会话（锁屏也能跑）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/lid-source-tests
swiftc -parse-as-library -O prototype/Support/Diagnostics.swift \
  prototype/Effects/FoldDriver.swift prototype/Effects/LidAngleSource.swift tests/LidSourceTests.swift \
  -o .build/lid-source-tests/lid-source
.build/lid-source-tests/lid-source
