#!/bin/bash
# R09：手柄按键表、游戏在前台真值表、同一时间只有一台手柄操作。纯 Foundation。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/gamepad-mapping-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/GamepadMapping.swift tests/support/WS2TestSupport.swift tests/GamepadMappingTests.swift \
  -o .build/gamepad-mapping-tests/tests
.build/gamepad-mapping-tests/tests
