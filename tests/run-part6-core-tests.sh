#!/usr/bin/env bash
# 第六份纯核：诊断尾部、owned scope、项目目录身份、列表选择、连接预算，以及第六份的仲裁。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/part6-core"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/InteractionCoordinator.swift" \
  "$ROOT/prototype/Core/WS2DiagnosticTail.swift" \
  "$ROOT/prototype/Core/WS2OwnedScope.swift" \
  "$ROOT/prototype/Support/WS2ProjectDirectory.swift" \
  "$ROOT/prototype/Core/WS2SelectionModel.swift" \
  "$ROOT/prototype/Core/WS2ConnectionBudget.swift" \
  "$ROOT/tests/Part6CoreTests.swift" -o "$OUT/part6-core-tests"
"$OUT/part6-core-tests" "$OUT/core-results.json"
