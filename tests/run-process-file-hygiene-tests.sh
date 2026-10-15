#!/bin/bash
# S05：子进程超时回收、journal 先 fsync 后改名、SPU 加速度计 Open 失败不 abort。不需要图形会话。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/process-file-hygiene
swiftc -swift-version 6 -parse-as-library -O -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/App/AirPodsBatterySource.swift prototype/Core/DeviceBattery.swift prototype/Core/BluetoothBatteryParse.swift \
  prototype/Recovery/DurableShadeJournal.swift \
  prototype/Effects/AppleSPUAccelerometer.swift prototype/Effects/FoldDriver.swift prototype/Core/MotionTilt.swift prototype/Core/FlickMotion.swift \
  tests/ProcessFileHygieneTests.swift -o .build/process-file-hygiene/run
.build/process-file-hygiene/run
