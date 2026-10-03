#!/bin/bash
# 输入钩子的开关、让位和改写资格。不创建事件 tap，不打开 HID。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/input-hook-tests
swiftc -swift-version 6 -parse-as-library \
  prototype/Core/Contracts.swift \
  prototype/Core/SmoothScroll.swift \
  prototype/Core/InputDeviceKind.swift \
  prototype/Core/SiriRemoteButtons.swift \
  prototype/Core/RemoteMode.swift \
  prototype/Core/FocusNavigator.swift \
  prototype/Core/MultitouchQualification.swift \
  prototype/Core/InputHookLifecycle.swift \
  prototype/Core/ScrollInstallPolicy.swift \
  prototype/Core/ScrollSession.swift \
  prototype/Core/InputFeatureGate.swift \
  prototype/Core/RemoteInputRouter.swift \
  tests/InputHookTests.swift \
  -o .build/input-hook-tests/input-hook
.build/input-hook-tests/input-hook
