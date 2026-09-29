#!/bin/bash
# 从哪来（欢迎窗口第二步“你之前常用哪个？”、设置里的“之前常用”）的存取和通知（纯逻辑，不碰用户的设置）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/switcher-origin-tests
swiftc -parse-as-library prototype/Core/SwitcherOrigin.swift \
  tests/SwitcherOriginTests.swift -o .build/switcher-origin-tests/origin
.build/switcher-origin-tests/origin
