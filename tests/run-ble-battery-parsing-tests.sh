#!/bin/bash
# 蓝牙电量探针的纯解析（不碰硬件）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ble-battery-parsing-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  tools/probes/BLEBatteryParsing.swift tests/BLEBatteryParsingTests.swift \
  -o .build/ble-battery-parsing-tests/run
.build/ble-battery-parsing-tests/run
