#!/bin/bash
# 规格 R25：触控板手指数按设备归属、丢了离手帧的过期恢复（纯逻辑，不碰真实输入）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/touch-ownership-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors prototype/Core/TouchOwnership.swift tests/TouchOwnershipTests.swift -o .build/touch-ownership-tests/tests
.build/touch-ownership-tests/tests
