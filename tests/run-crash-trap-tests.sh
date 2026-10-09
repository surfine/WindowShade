#!/bin/bash
# S03：必崩点守卫（键码越界、AX 类型不符、无屏幕）的纯函数测试。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/crash-trap-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Support/SecureLogFile.swift \
  prototype/Support/Diagnostics.swift \
  prototype/Private/DockBridge.swift \
  tests/CrashTrapTests.swift \
  -o .build/crash-trap-tests/tests
.build/crash-trap-tests/tests
