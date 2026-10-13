#!/bin/bash
# PERF-08：活动来源的轮询节奏。音乐关着时不该每 2 秒通问一次，通知要能立刻触发对账。
# 会真的建一个 NotchActivitySources、跑主 run loop 约 6 秒，但不动麦克风、不问自动化权限。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-polling-tests
swiftc -parse-as-library -O \
  prototype/Core/WSL10n.swift \
  prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift \
  prototype/App/NotchActivityPollPolicy.swift \
  prototype/App/NotchActivitySources.swift \
  prototype/App/NowPlayingStream.swift \
  prototype/App/NowPlayingArtwork.swift \
  prototype/Core/ArtworkPalette.swift \
  prototype/App/CalendarSource.swift prototype/Core/CalendarActivity.swift \
  prototype/Core/NowPlayingStreamParser.swift prototype/Core/NowPlayingCardLogic.swift \
  tests/NotchPollingTests.swift \
  -o .build/notch-polling-tests/tests
.build/notch-polling-tests/tests
