#!/bin/bash
# 侧拉边框：底的选择（减少透明度 -> 不透明）、维护定时器生命周期、几何常量不变（对源码核对）。
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME=prototype/App/SlideOverChrome.swift
for needle in 'static let thickness: CGFloat = 10' 'static let handleSize: CGFloat = 36' 'static let defaultCornerRadius: CGFloat = 17'; do
  grep -qF "$needle" "$CHROME" || { echo "FAIL: geometry constant changed: $needle"; exit 1; }
done
! grep -q 'CGGradient' "$CHROME" || { echo "FAIL: hand-drawn gradient is back"; exit 1; }
mkdir -p .build/slideover-chrome-tests
GLASS_DEFINE=()
if [ -f "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  GLASS_DEFINE=(-DWINDOWSHADE_SDK_HAS_GLASS)
fi
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  ${GLASS_DEFINE[@]+"${GLASS_DEFINE[@]}"} \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/App/SlideOverGlass.swift tests/SlideOverChromeTests.swift \
  -framework Cocoa -o .build/slideover-chrome-tests/tests
.build/slideover-chrome-tests/tests
