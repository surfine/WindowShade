#!/bin/bash
# R01：低电量/热状态降级档的映射与通知（不需要图形会话）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/power-policy-tests
swiftc -parse-as-library -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/App/PowerPolicy.swift \
  tests/PowerPolicyTests.swift \
  -o .build/power-policy-tests/tests
.build/power-policy-tests/tests
