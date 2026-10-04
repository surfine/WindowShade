#!/bin/bash
# 静音命令会话与蓝牙证据分级。不编译 App，不碰正在改的 runtime。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/silent-prep-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift \
  prototype/Core/WS2SilentCatalog.swift \
  prototype/Core/WS2SilentSession.swift \
  prototype/Core/WS2SilentExecution.swift \
  prototype/Core/WS2DeviceEvidence.swift \
  prototype/Core/WS2HeadGesture.swift \
  prototype/Core/WS2CameraChoice.swift \
  prototype/Core/WS2ScreenDistance.swift \
  prototype/Core/WS2Posture.swift \
  prototype/Core/WS2SilentProductPort.swift \
  prototype/Core/WS2SilentDraft.swift \
  prototype/Core/WS2SilentGates.swift \
  prototype/Core/WS2SilentPhrases.swift \
  prototype/Core/WS2SilentSecurity.swift \
  prototype/Core/WS2SilentCopy.swift \
  prototype/Core/PresenceLock.swift \
  prototype/Core/WS2AwaySimulation.swift \
  prototype/Core/WS2JournalWrite.swift \
  prototype/Core/WS2HookConfigPreview.swift \
  tests/SilentPrepTests.swift \
  -o .build/silent-prep-tests/silent-prep
.build/silent-prep-tests/silent-prep
