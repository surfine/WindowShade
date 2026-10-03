#!/usr/bin/env bash
# 第六份进程通道：真实 Python 子进程、拆包、背压、诊断尾部、直接终止状态。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/part6-process"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Core/WS2DiagnosticTail.swift" \
  "$ROOT/prototype/Support/WS2DuplexProcess.swift" \
  "$ROOT/tests/Part6ProcessTests.swift" -o "$OUT/part6-process-tests"
"$OUT/part6-process-tests" "$ROOT/tests/part6-child.py" "$OUT/process-results.json"
