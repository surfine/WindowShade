#!/usr/bin/env bash
# 第二轮第 2 份的纯核：共享交互租约、Codex 固定协议、远端准入门、蓝牙读期限。
# 证据与原始载荷保留在 docs/handoff/chatgpt-review-2/part2/validation/。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/part2-core"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/InteractionCoordinator.swift" \
  "$ROOT/prototype/Core/CodexWire.swift" \
  "$ROOT/prototype/Core/WS2StrictJSON.swift" \
  "$ROOT/prototype/Core/RemoteSessionGate.swift" \
  "$ROOT/prototype/Core/PresenceReadDeadline.swift" \
  "$ROOT/tests/Part2CoreTests.swift" -o "$BUILD/part2-core-tests"
"$BUILD/part2-core-tests" "$ROOT/docs/handoff/chatgpt-review-2/part2/validation/codex-outbound.ndjson"
