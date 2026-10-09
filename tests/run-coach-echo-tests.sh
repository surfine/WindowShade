#!/usr/bin/env bash
# R13：卡住提示的键帽回声与提前收回（纯判定）。不碰真机。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/coach-echo-tests"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/CoachEcho.swift" "$ROOT/tests/CoachEchoTests.swift" -o "$OUT/coach-echo-tests"
"$OUT/coach-echo-tests"
