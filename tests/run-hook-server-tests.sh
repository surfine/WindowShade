#!/usr/bin/env bash
# 编程会话 hook 服务端（WS2HookServer）：解析、状态转移、socket 权限与关掉后删文件。
# socket 只开在 /tmp 下的临时目录里，不碰用户的 Application Support。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/hook-server"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/AgentSessions.swift" \
  "$ROOT/prototype/Support/WS2AtomicConfiguration.swift" "$ROOT/prototype/Support/WS2HookConfiguration.swift" "$ROOT/prototype/Support/WS2UnixSocket.swift" \
  "$ROOT/prototype/App/WS2HookServer.swift" "$ROOT/tests/support/WS2TestSupport.swift" \
  "$ROOT/tests/HookServerTests.swift" -o "$BUILD/hook-server-tests"
"$BUILD/hook-server-tests"
