#!/bin/bash
# 隐私页导出的纯逻辑：只编数据源、导出函数和测试，不碰界面。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/privacy-export-tests
swiftc -swift-version 6 -parse-as-library prototype/App/WS2PrivacyData.swift prototype/App/WS2PrivacyExport.swift \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  tests/PrivacyExportTests.swift -o .build/privacy-export-tests/export
.build/privacy-export-tests/export
