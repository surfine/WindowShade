#!/usr/bin/env bash
# 刷脸日志里的随身设备在场注记（纯格式化，不读蓝牙、不判断身份）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-presence-note-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/PresenceLock.swift prototype/Core/FacePresenceNote.swift \
  tests/support/WS2TestSupport.swift tests/FacePresenceNoteTests.swift \
  -o .build/face-presence-note-tests/face-presence-note
.build/face-presence-note-tests/face-presence-note
