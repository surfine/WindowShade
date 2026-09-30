#!/bin/bash
# 收起 / 展开音效：调用方立即返回、播放在后台队列上（设备冷启动 250–500ms 不再卡主线程）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/shade-sound-tests
swiftc -parse-as-library prototype/App/ShadeSoundPlayer.swift tests/ShadeSoundTests.swift \
  -o .build/shade-sound-tests/sound
.build/shade-sound-tests/sound
