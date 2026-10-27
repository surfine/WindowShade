#!/usr/bin/env bash
# A2 连接/断开往返：临时 HOME，不碰用户配置。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/hook-config-store
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/WS2HookConfigPreview.swift \
  prototype/Support/WS2HookConfiguration.swift prototype/App/WS2ConductorSettingsCore.swift \
  prototype/App/WS2HookConfigStore.swift \
  tests/HookConfigStoreTests.swift -o .build/hook-config-store/run
.build/hook-config-store/run
