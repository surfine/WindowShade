#!/bin/bash
# v4 源码验收。不把 AppKit、真机或资格审查算成已经跑过。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/delta-review-v4
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift \
  prototype/Core/InteractionCoordinator.swift \
  prototype/Core/PiPFrameGate.swift \
  prototype/Core/WS2SilentCatalog.swift \
  prototype/Core/WS2SilentIntent.swift \
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
  tests/DeltaReviewV4Tests.swift \
  -o .build/delta-review-v4/delta-review-v4
.build/delta-review-v4/delta-review-v4
