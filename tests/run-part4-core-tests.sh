#!/usr/bin/env bash
# 第四份纯核：审批 review 与一次性编码、Companion 有界帧、输入准入、窗口所有权收据、
# 番茄钟 pending/active 分离，以及前三份的 CodexWire。证据写进 .build/part4-core/。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/part4-core"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/CodexWire.swift" \
  "$ROOT/prototype/Core/WS2StrictJSON.swift" \
  "$ROOT/prototype/Core/FocusTimer.swift" \
  "$ROOT/prototype/Core/WS2CompanionFrame.swift" \
  "$ROOT/prototype/Core/WS2ApprovalReview.swift" \
  "$ROOT/prototype/Core/WS2DeviceInputGate.swift" \
  "$ROOT/prototype/Core/WS2FocusWindowOwnership.swift" \
  "$ROOT/tests/Part4CoreTests.swift" -o "$OUT/part4-core-tests"
"$OUT/part4-core-tests" "$OUT"
