#!/bin/bash
# 先跑 LidFeed（F05：读数在 lid 队列消化，只在有变化时回主线程）：不接硬件，哪台机器都能跑。
# 再应用真实的 LidAngleSource：能拿到读数，且走「订阅推送 + 1Hz 看门狗」而不是 4Hz 轮询。
# 后一段不需要图形会话（锁屏也能跑），但依赖这台机器真有会推送的盖角传感器。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/lid-source-tests
SOURCES=(prototype/Support/SecureLogFile.swift prototype/Support/Diagnostics.swift
  prototype/Core/FlickMotion.swift prototype/Core/LidGesture.swift
  prototype/Effects/FoldDriver.swift prototype/Effects/LidReconnectBackoff.swift prototype/Effects/LidAngleSource.swift)
swiftc -parse-as-library -O "${SOURCES[@]}" prototype/Core/WSL10n.swift tests/LidFeedTests.swift -o .build/lid-source-tests/lid-feed
.build/lid-source-tests/lid-feed
swiftc -parse-as-library -O "${SOURCES[@]}" prototype/Core/WSL10n.swift tests/LidSourceTests.swift -o .build/lid-source-tests/lid-source
.build/lid-source-tests/lid-source
