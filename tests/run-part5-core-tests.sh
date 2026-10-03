#!/usr/bin/env bash
# 第五份纯核：有界出站队列、语义输入票据、窗口阶段计划、配对编排与持久快照。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/part5-core"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/WS2FocusWindowOwnership.swift" \
  "$ROOT/prototype/Core/WS2DeviceInputGate.swift" \
  "$ROOT/prototype/Core/PairingAttemptWindow.swift" \
  "$ROOT/prototype/Core/PairingTLV.swift" \
  "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Core/WS2SemanticInputRouter.swift" \
  "$ROOT/prototype/Core/WS2FocusEffectPlan.swift" \
  "$ROOT/prototype/Support/WS2PeerRepository.swift" \
  "$ROOT/prototype/Support/WS2PairSetupServer.swift" \
  "$ROOT/tests/Part5CoreTests.swift" -o "$OUT/part5-core-tests"
"$OUT/part5-core-tests" "$OUT/core-results.json"
