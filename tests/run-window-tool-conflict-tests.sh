#!/bin/bash
# window-tool-conflict：纯逻辑判定（不需要图形会话，不碰系统）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/window-tool-conflict-tests
swiftc -parse-as-library -target arm64-apple-macos15.0 prototype/Core/WindowToolConflict.swift tests/WindowToolConflictTests.swift -o .build/window-tool-conflict-tests/window-tool-conflict
.build/window-tool-conflict-tests/window-tool-conflict
