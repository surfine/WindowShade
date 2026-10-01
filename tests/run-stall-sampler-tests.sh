#!/bin/bash
# 卡顿采样器：一次长卡顿分段抓多张栈（主线程真的阻塞 1.1 秒）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/stall-sampler-tests
swiftc -parse-as-library prototype/Support/Diagnostics.swift tests/StallSamplerTests.swift \
  -o .build/stall-sampler-tests/sampler
.build/stall-sampler-tests/sampler
