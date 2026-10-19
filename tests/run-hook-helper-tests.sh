#!/usr/bin/env bash
# 端到端：真实 hook helper 进程 ↔ 真实服务端（临时 socket）。不发真实模型请求。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/hook-helper"
mkdir -p "$BUILD"
SWIFTC="${SWIFTC:-swiftc}"
FLAGS=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library)

"$SWIFTC" "${FLAGS[@]}" \
  "$ROOT/prototype/Support/WS2AtomicConfiguration.swift" \
  "$ROOT/prototype/Support/WS2HookConfiguration.swift" \
  "$ROOT/prototype/Support/WS2UnixSocket.swift" \
  "$ROOT/prototype/Support/WS2BoundedInput.swift" \
  "$ROOT/prototype/Core/TerminalIdentity.swift" \
  "$ROOT/tools/ws2-hook/main.swift" \
  -o "$BUILD/WindowShadeHook"

"$SWIFTC" "${FLAGS[@]}" \
  "$ROOT/prototype/Core/WSL10n.swift" \
  "$ROOT/prototype/Core/PrivacyPaneName.swift" \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/AgentSessions.swift" \
  "$ROOT/prototype/Core/TerminalIdentity.swift" \
  "$ROOT/prototype/Support/WS2AtomicConfiguration.swift" \
  "$ROOT/prototype/Support/WS2HookConfiguration.swift" \
  "$ROOT/prototype/Support/WS2UnixSocket.swift" \
  "$ROOT/prototype/App/WS2HookServer.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" \
  "$ROOT/tests/HookHelperTests.swift" \
  -o "$BUILD/hook-helper-tests"

"$BUILD/hook-helper-tests" "$BUILD/WindowShadeHook"
