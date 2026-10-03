#!/usr/bin/env bash
# 第五份进程通道：真实子进程的拆包、背压与每批 binding（第六份之后由 run-part6-process-tests.sh 扩展）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/part5-process"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Core/WS2DiagnosticTail.swift" \
  "$ROOT/prototype/Support/WS2DuplexProcess.swift" \
  "$ROOT/tests/Part5ProcessTests.swift" -o "$OUT/part5-process-tests"
"$OUT/part5-process-tests" "$ROOT/tests/part5-fake-child.py" "$OUT/process-results.json"
