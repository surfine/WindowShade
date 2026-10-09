#!/bin/bash
# 口型模板匹配、录制质量门与按屏头部基线。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ws2-mouth .build/mouth-template-tests
swiftc -module-cache-path .build/ws2-mouth/cache -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
 prototype/Core/WS2SilentCatalog.swift prototype/Core/WS2SilentPhrases.swift prototype/Core/WS2MouthTemplates.swift prototype/Core/WS2DeviceEvidence.swift tests/WS2MouthTemplatesTests.swift -o .build/ws2-mouth/tests
.build/ws2-mouth/tests
swiftc -module-cache-path .build/ws2-mouth/cache -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/WS2SilentCatalog.swift prototype/Core/WS2SilentPhrases.swift prototype/Core/WS2MouthTemplates.swift prototype/Core/WS2HeadGesture.swift \
  tests/HeadMouthTests.swift -o .build/mouth-template-tests/mouth
.build/mouth-template-tests/mouth
