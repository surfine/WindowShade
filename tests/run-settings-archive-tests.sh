#!/bin/bash
# 规格 R5：设置的导出、导入与迁移前备份的纯逻辑。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/settings-archive-tests
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/SettingsArchive.swift tests/SettingsArchiveTests.swift -o .build/settings-archive-tests/run
.build/settings-archive-tests/run
