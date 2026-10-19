#!/usr/bin/env bash
# Claude stream-json 的纯解析：init / 增量 / assistant / 权限拒绝 / result；不启动进程。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/claude-wire"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WireJSON.swift" \
  "$ROOT/prototype/Core/ClaudeWire.swift" \
  "$ROOT/tests/ClaudeWireTests.swift" \
  -o "$BUILD/claude-wire-tests"
"$BUILD/claude-wire-tests" "$@"
