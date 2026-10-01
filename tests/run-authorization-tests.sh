#!/bin/bash
# 一次性授权账本：纯逻辑，不碰界面和 Touch ID（v4 交接 TXN-01…08）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/authorization-tests
swiftc -swift-version 6 -parse-as-library \
  prototype/Core/SessionLockState.swift prototype/Core/AuthorizationModels.swift prototype/Core/AuthorizationLedger.swift \
  tests/AuthorizationLedgerTests.swift -o .build/authorization-tests/ledger
.build/authorization-tests/ledger
