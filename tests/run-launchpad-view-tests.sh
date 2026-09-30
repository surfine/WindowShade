#!/bin/bash
# 需要 macOS 图形会话；使用合成应用，不显示窗口、不改用户数据。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/launchpad-tests
GLASS_DEFINE=()
if [ -f "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  GLASS_DEFINE=(-DWINDOWSHADE_SDK_HAS_GLASS)
fi
swiftc ${GLASS_DEFINE[@]+"${GLASS_DEFINE[@]}"} prototype/Core/LaunchpadModel.swift prototype/Core/NotchActivities.swift \
  prototype/App/Launchpad.swift prototype/App/LaunchpadBackdrop.swift prototype/App/LaunchpadView.swift \
  prototype/App/LaunchpadFolders.swift prototype/App/LaunchpadLibrary.swift prototype/App/LaunchpadArtwork.swift prototype/App/LaunchpadToday.swift prototype/App/LaunchpadActivities.swift prototype/App/NotchActivitySymbol.swift prototype/App/LaunchpadOpenWith.swift \
  tests/LaunchpadViewTests.swift -o .build/launchpad-tests/view
.build/launchpad-tests/view
