#!/bin/bash
# 1.0.17 精简：设置侧栏的可见页、行号映射与「上次看的页」还原（纯逻辑，不编整个 App）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/settings-sections-tests
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/App/SettingsSections.swift prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  tests/SettingsSectionsTests.swift -o .build/settings-sections-tests/run
.build/settings-sections-tests/run
