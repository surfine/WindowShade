#!/usr/bin/env bash
# Claude 会话的进程级验收：假 CLI 走发送/增量/result/停止/resume；不发真实模型请求。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/claude-session"
mkdir -p "$OUT"
cc -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  -c "$ROOT/prototype/Native/WS2Child.c" -o "$OUT/WS2Child.o"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -I "$ROOT/prototype/Native" "$OUT/WS2Child.o" \
  "$ROOT/prototype/Core/WireJSON.swift" \
  "$ROOT/prototype/Core/ClaudeWire.swift" \
  "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Core/WS2DiagnosticTail.swift" \
  "$ROOT/prototype/Support/WS2DuplexProcess.swift" \
  "$ROOT/prototype/App/WS2OwnedClaudeSession.swift" \
  "$ROOT/tests/ClaudeSessionTests.swift" \
  -o "$OUT/claude-session-tests"
"$OUT/claude-session-tests" "$ROOT/tests/fixtures/fake-claude.py" "$@"
