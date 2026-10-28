#!/usr/bin/env bash
# F1-B 桥的纯逻辑侧（无网络）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/homeplay-presence
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library -D WS2_HOMEPLAY_PRESENCE_TESTING \
  prototype/Core/Contracts.swift prototype/Core/PresenceLock.swift \
  prototype/App/WS2HomePlayPresenceSource.swift \
  tests/HomePlayPresenceTests.swift \
  -o .build/homeplay-presence/run
.build/homeplay-presence/run
