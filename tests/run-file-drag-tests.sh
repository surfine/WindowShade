#!/bin/bash
# FS-03：拖文件靠近刘海的判定（纯逻辑加一块私有剪贴板）。不需要图形会话，不碰系统的拖动剪贴板。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/file-drag-tests
swiftc -parse-as-library -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/FileShelfModel.swift \
  prototype/App/FileShelfStore.swift prototype/Core/ReleaseDefaults.swift \
  prototype/App/FileDragSensor.swift \
  tests/FileDragSensorTests.swift \
  -o .build/file-drag-tests/tests
.build/file-drag-tests/tests
