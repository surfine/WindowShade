#!/bin/bash
# 规格 R28：系统设置里辅助功能那一栏在 macOS 27 改名。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/privacy-pane-name-tests
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/PrivacyPaneName.swift prototype/Core/WSL10n.swift tests/PrivacyPaneNameTests.swift -o .build/privacy-pane-name-tests/run
.build/privacy-pane-name-tests/run
