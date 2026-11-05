#!/bin/bash
# 离开就锁的蓝牙在场来源（App/WS2BluetoothPresenceSource.swift）：假接缝驱动通知，不碰真蓝牙。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/presence-tests
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -module-cache-path "$PWD/.build/module-cache" \
  prototype/Core/Contracts.swift prototype/Core/PresenceLock.swift prototype/Core/WS2BluetoothPresenceModel.swift \
  prototype/App/WS2BluetoothPresenceSource.swift tests/support/WS2TestSupport.swift tests/WS2BluetoothPresenceSourceTests.swift \
  -o .build/presence-tests/presence-source
.build/presence-tests/presence-source
