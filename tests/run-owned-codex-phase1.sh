#!/usr/bin/env bash
# 工单 02 阶段一：真跑本机 codex app-server。会消耗你的 Codex 额度；不发 allow 消息。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX="${1:-/opt/homebrew/bin/codex}"
OUT="$ROOT/.build/owned-codex"
mkdir -p "$OUT"
if [ ! -x "$CODEX" ]; then echo "NOT RUN: no codex at $CODEX"; exit 78; fi
# WS2DuplexProcess 依赖原生 C 模块 WS2ProcessNative（prototype/Native），和 run-duplex-process-tests.sh 一样先编出来。
cc -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 -c "$ROOT/prototype/Native/WS2Child.c" -o "$OUT/WS2Child.o"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -I "$ROOT/prototype/Native" "$OUT/WS2Child.o" \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/WireJSON.swift" \
  "$ROOT/prototype/Core/WS2StrictJSON.swift" \
  "$ROOT/prototype/Core/CodexWire.swift" \
  "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Core/WS2DiagnosticTail.swift" \
  "$ROOT/prototype/Support/WS2DuplexProcess.swift" \
  "$ROOT/tests/OwnedCodexPhase1.swift" -o "$OUT/phase1"
"$OUT/phase1" "$CODEX" | tee "$OUT/phase1.txt"
