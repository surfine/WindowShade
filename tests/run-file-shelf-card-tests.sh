#!/bin/bash
# FS-04：文件架卡的纯逻辑（那一排的末格、拖出拷贝 / ⌘ 移动、全部移出撤销、失效格、右键与读屏动作）。
# 不需要图形会话；全部移出撤销那一段用临时目录里的真文件。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/file-shelf-card-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/NotchSentence.swift prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift \
  prototype/Core/NotchRow.swift prototype/Core/FileShelfModel.swift prototype/App/FileShelfStore.swift \
  tests/support/WS2TestSupport.swift tests/FileShelfCardTests.swift \
  -o .build/file-shelf-card-tests/tests
.build/file-shelf-card-tests/tests
