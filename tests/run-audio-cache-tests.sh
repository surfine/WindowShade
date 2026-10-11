#!/bin/bash
# AirPods 设备枚举缓存：新建即脏、store 后可复用、markDirty 强制重算、超龄不复用（纯逻辑）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/audio-cache-tests
swiftc -parse-as-library -O prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift prototype/App/NotchActivityPollPolicy.swift prototype/App/NotchActivitySources.swift \
  prototype/App/NowPlayingStream.swift prototype/App/NowPlayingArtwork.swift prototype/Core/NowPlayingStreamParser.swift prototype/Core/NowPlayingCardLogic.swift \
  prototype/Core/ArtworkPalette.swift \
  prototype/App/CalendarSource.swift prototype/Core/CalendarActivity.swift \
  tests/AudioDeviceCacheTests.swift -o .build/audio-cache-tests/cache
.build/audio-cache-tests/cache
