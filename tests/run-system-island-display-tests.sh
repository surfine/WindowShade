#!/bin/bash
# 第 38–43 条：系统灵动岛让开的名单（空表）、摄像头安静、活动跟着正在用的屏（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/system-island-display-tests
swiftc -O -parse-as-library prototype/Core/SystemIslandPolicy.swift prototype/Core/CameraQuietPolicy.swift prototype/Core/ActiveDisplayTracker.swift tests/SystemIslandAndDisplayTests.swift -o .build/system-island-display-tests/run
.build/system-island-display-tests/run
