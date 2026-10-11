#!/bin/bash
# FS-01/FS-02：文件架模型（纯逻辑）与存取（临时目录里的真文件、真书签）。不需要图形会话。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/file-shelf-tests
swiftc -parse-as-library -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/FileShelfModel.swift \
  prototype/App/FileShelfStore.swift prototype/Core/ReleaseDefaults.swift \
  tests/FileShelfTests.swift \
  -o .build/file-shelf-tests/tests
.build/file-shelf-tests/tests
