#!/usr/bin/env bash
# PROC04：父进程写一行后退出、短命子孙持有描述符时，退出通知会不会迟到。结果如实记录，不改阈值。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/part6-exit"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Core/WS2DiagnosticTail.swift" \
  "$ROOT/prototype/Support/WS2DuplexProcess.swift" \
  "$ROOT/tests/ExitInheritanceProbe.swift" -o "$OUT/exit-probe"
"$OUT/exit-probe" "$ROOT/tests/part6-child.py" "$OUT/exit-inheritance-probe.json"
