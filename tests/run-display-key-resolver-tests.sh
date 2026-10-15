#!/bin/bash
# 规格 R27：按显示器落盘的设置先认 UUID、再退回旧编号。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/display-key-resolver-tests
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/DisplayKeyResolver.swift tests/DisplayKeyResolverTests.swift -o .build/display-key-resolver-tests/run
.build/display-key-resolver-tests/run
