#!/usr/bin/env bash
# 工单 01 第三步：真实 CLI 驱动 LaunchController（隔离 profile，不打开登录页，不发有副作用的命令）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX="${1:-/opt/homebrew/bin/codex}"
OUT="$ROOT/.build/owned-codex-controller"
mkdir -p "$OUT"
[ -x "$CODEX" ] || { echo "NOT RUN: no codex at $CODEX"; exit 78; }
NATIVE="$ROOT/.build/native"
mkdir -p "$NATIVE"
cc -std=c11 -O2 -Wall -Wextra -Werror -c "$ROOT/prototype/Native/WS2Child.c" -o "$NATIVE/WS2Child.o"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -I "$ROOT/prototype/Native" "$NATIVE/WS2Child.o" \
  "$ROOT"/prototype/Core/{Contracts,WS2QuitBarrier,WS2StrictJSON,CodexWire,WS2OwnedProtocolHost,WS2BoundedOutbox,WS2DiagnosticTail,WS2OwnedScope,AgentSessions}.swift \
  "$ROOT"/prototype/Support/{WS2ProjectDirectory,WS2LocalLaunchProfile,WS2VersionProbe,WS2DuplexProcess}.swift \
  "$ROOT"/prototype/App/{WS2OwnedCodexSession,WS2OwnedLaunchController}.swift \
  "$ROOT/tests/OwnedCodexRealController.swift" -o "$OUT/controller"
"$OUT/controller" "$CODEX" | tee "$OUT/run.txt"
