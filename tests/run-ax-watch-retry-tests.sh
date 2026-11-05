#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/ax-watch-retry-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/AXWatchRetryPolicy.swift \
  tests/AXWatchRetryPolicyTests.swift \
  -o "$OUT"
"$OUT"
