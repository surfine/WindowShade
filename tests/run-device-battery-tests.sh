#!/bin/bash
# 设备电量纯逻辑：身份、新鲜度、低电量档位、连接事件（交接 v2 BATTERY-ISLAND-ACCEPTANCE 的一部分）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/device-battery-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/DeviceBattery.swift tests/DeviceBatteryTests.swift \
  -o .build/device-battery-tests/battery
.build/device-battery-tests/battery
