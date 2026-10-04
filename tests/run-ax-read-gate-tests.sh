#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  prototype/Core/AXReadGate.swift \
  tests/AXReadGateTests.swift \
  -o /tmp/ax-read-gate-tests
/tmp/ax-read-gate-tests
