#!/bin/bash
# 1-4：iPhone 遥控器键码表、松开才算、触控 60/150 门槛、会话时限（纯逻辑，不碰网络和加密）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/companion-hid-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/Contracts.swift prototype/Core/CompanionHIDMap.swift \
  tests/CompanionHIDMapTests.swift -o .build/companion-hid-tests/hid
.build/companion-hid-tests/hid
