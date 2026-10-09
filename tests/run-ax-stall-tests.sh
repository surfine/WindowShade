#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/ax-stall-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Window/AXStallBreaker.swift \
  tests/AXStallBreakerTests.swift \
  -o "$OUT"
"$OUT"
