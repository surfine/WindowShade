#!/bin/bash
# 欢迎窗口三步（M4 样片）：状态机、四种说明行、减少动态效果无位移、页码读屏“第 n 页”、键帽错开（纯逻辑，不开窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/welcome-flow-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/SwitcherOrigin.swift prototype/Core/FlickMotion.swift prototype/App/WelcomeFlow.swift \
  tests/WelcomeFlowTests.swift -o .build/welcome-flow-tests/flow
.build/welcome-flow-tests/flow
