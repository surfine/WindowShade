#!/bin/bash
# 规格 R21：关卷帘条后的退出策略分类（纯逻辑）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/close-quit-policy-tests
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -target arm64-apple-macos15.0 \
  prototype/Core/CloseQuitPolicy.swift tests/CloseQuitPolicyTests.swift -o .build/close-quit-policy-tests/run
.build/close-quit-policy-tests/run
