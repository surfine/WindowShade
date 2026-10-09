#!/bin/bash
# S02：Dock 工具调用时限与退出不挂起（不需要图形会话，约 15 秒）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/dock-tool-deadline-tests
swiftc -parse-as-library -O \
  prototype/Support/SecureLogFile.swift \
  prototype/Support/Diagnostics.swift \
  prototype/App/DockToolRunner.swift \
  tests/DockToolDeadlineTests.swift \
  -o .build/dock-tool-deadline-tests/tests
.build/dock-tool-deadline-tests/tests
