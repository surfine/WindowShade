#!/usr/bin/env bash
# F04：子进程监督事件驱动（退出事件源 + 仅停止后的短期收割定时器）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/duplex-process"
mkdir -p "$OUT"
NATIVE="$ROOT/.build/native"
mkdir -p "$NATIVE"
cc -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 -c "$ROOT/prototype/Native/WS2Child.c" -o "$NATIVE/WS2Child.o"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -I "$ROOT/prototype/Native" "$NATIVE/WS2Child.o" \
  "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Core/WS2DiagnosticTail.swift" \
  "$ROOT/prototype/Support/WS2DuplexProcess.swift" \
  "$ROOT/tests/DuplexProcessTests.swift" -o "$OUT/duplex-process-tests"
"$OUT/duplex-process-tests" "$ROOT/tests/duplex-child.py" "$OUT/process-results.json"
