#!/bin/bash
# 欢迎窗口（1.0.18 A1 / A2 / T / U1）：状态机、练习状态、T 分段与自动往下走、授权行、页码读屏、窗口高度（纯逻辑，不开窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/welcome-flow-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/SwitcherOrigin.swift prototype/Core/FlickMotion.swift prototype/App/WelcomeFlow.swift \
  tests/WelcomeFlowTests.swift -o .build/welcome-flow-tests/flow
.build/welcome-flow-tests/flow
