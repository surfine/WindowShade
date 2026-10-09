#!/usr/bin/env bash
# 协调器照文法：放行不抢手势、点被消耗、放行排队、0.6 秒合并。纯 Foundation，不碰 AppKit 与真机。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/interaction-coordinator"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/InteractionCoordinator.swift" \
  "$ROOT/tests/InteractionCoordinatorRulesTests.swift" -o "$OUT/interaction-coordinator-tests"
"$OUT/interaction-coordinator-tests"
