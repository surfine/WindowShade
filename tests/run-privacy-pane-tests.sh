#!/bin/bash
# 隐私一栏的纯逻辑：读取次数、哪些行出现、一行怎么摆、值怎么写、文案禁用字样、没有定时读取，
# 以及启动时一次性清理旧的 /tmp/windowshade.log（拒绝符号链接）。界面由 run-appkit-tests.sh 的 SettingsNavigationTests 看。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/privacy-pane-tests
swiftc -swift-version 6 -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  prototype/App/WS2PrivacyData.swift prototype/App/WS2PrivacyModel.swift \
  prototype/Core/DeviceBattery.swift prototype/App/DeviceBatteryCopy.swift prototype/Core/NotchSentence.swift \
  prototype/Support/SecureLogFile.swift prototype/Support/Diagnostics.swift \
  tests/PrivacyPaneTests.swift \
  -framework Cocoa -o .build/privacy-pane-tests/pane
.build/privacy-pane-tests/pane
