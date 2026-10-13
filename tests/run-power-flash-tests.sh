#!/bin/bash
# 电量那一下（PWR-2）与设备提醒新外观文案（DEV-1）的纯逻辑。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/power-flash-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/DeviceBattery.swift prototype/Core/PowerFlash.swift prototype/Core/NotchSentence.swift \
  prototype/Core/WSL10n.swift \
  prototype/App/DeviceBatteryCopy.swift tests/PowerFlashTests.swift -o .build/power-flash-tests/flash
.build/power-flash-tests/flash
