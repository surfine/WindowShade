#!/bin/bash
# 离开就锁的蓝牙在场判定（纯模型，不碰 IOBluetooth）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/presence-tests
swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path "$PWD/.build/module-cache" \
  prototype/Core/WS2BluetoothPresenceModel.swift tests/WS2BluetoothPresenceTests.swift \
  -o .build/presence-tests/presence-model
.build/presence-tests/presence-model
