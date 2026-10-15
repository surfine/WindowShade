#!/bin/bash
# F07：平滑滚动逐帧换算与显示链接的收尾（不创建事件 tap，不发真实事件）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/scroll-frame-tests
swiftc -swift-version 6 -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/Contracts.swift \
  prototype/Core/SmoothScroll.swift \
  prototype/Core/InputDeviceKind.swift \
  prototype/Core/InputHookLifecycle.swift \
  prototype/Core/ScrollSession.swift \
  prototype/App/ScrollTap.swift prototype/Core/EventTapHealth.swift prototype/Support/SendableSystemHandles.swift \
  tests/ScrollFrameTests.swift \
  -o .build/scroll-frame-tests/scroll-frame
.build/scroll-frame-tests/scroll-frame
