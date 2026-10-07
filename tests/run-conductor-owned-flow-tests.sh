#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/conductor-owned-flow"
mkdir -p "$OUT/module-cache"
cc -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 -c "$ROOT/prototype/Native/WS2Child.c" -o "$OUT/WS2Child.o"
swiftc -module-cache-path "$OUT/module-cache" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -I "$ROOT/prototype/Native" "$OUT/WS2Child.o" \
  "$ROOT"/prototype/Core/{Contracts,WS2QuitBarrier,WS2StrictJSON,CodexWire,WS2OwnedProtocolHost,WS2BoundedOutbox,WS2DiagnosticTail,WS2OwnedScope,AgentSessions}.swift \
  "$ROOT"/prototype/Support/{WS2ProjectDirectory,WS2LocalLaunchProfile,WS2VersionProbe,WS2DuplexProcess}.swift \
  "$ROOT"/prototype/App/{WS2OwnedCodexSession,WS2OwnedLaunchController}.swift \
  "$ROOT/tests/ConductorOwnedFlowTests.swift" -o "$OUT/conductor-owned-flow"
"$OUT/conductor-owned-flow" "$ROOT/tests/fixtures/conductor-backend.py"
