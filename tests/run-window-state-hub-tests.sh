#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/window-state-hub-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Support/SkyLightFramework.swift prototype/Support/MainTimer.swift \
  prototype/Private/SkyLightNotify.swift prototype/Window/WindowStateHub.swift \
  tests/WindowStateHubTests.swift \
  -framework Cocoa -o .build/window-state-hub-tests/tests
.build/window-state-hub-tests/tests
