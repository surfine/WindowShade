#!/usr/bin/env bash
# 指挥页 ClaudeConductor：缺失/发送/回答中/结束/停止/续接，用假 CLI，不发真实模型请求。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/claude-conductor"
mkdir -p "$OUT"
cc -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -c "$ROOT/prototype/Native/WS2Child.c" -o "$OUT/WS2Child.o"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -I "$ROOT/prototype/Native" "$OUT/WS2Child.o" \
  "$ROOT/prototype/Core/WireJSON.swift" \
  "$ROOT/prototype/Core/ClaudeWire.swift" \
  "$ROOT/prototype/Core/ClaudeConductorRules.swift" \
  "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Core/WS2DiagnosticTail.swift" \
  "$ROOT/prototype/Support/WS2DuplexProcess.swift" \
  "$ROOT/prototype/App/WS2OwnedClaudeSession.swift" \
  "$ROOT/prototype/App/ClaudeConductor.swift" \
  "$ROOT/tests/ClaudeConductorTests.swift" \
  -o "$OUT/claude-conductor-tests"
"$OUT/claude-conductor-tests" "$ROOT/tests/fixtures/fake-claude.py" "$ROOT/tests/fixtures/fake-claude-auth-expired.py" "$@"
