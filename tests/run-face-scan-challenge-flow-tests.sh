#!/bin/bash
# 刷脸实验：主人匹配后再做随机转头挑战的衔接（纯逻辑，只产证据）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-scan-challenge-flow-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/FaceScanChallengeFlow.swift prototype/Core/FaceGestureTracker.swift \
  prototype/Core/SessionLockState.swift prototype/Core/FaceScanGuard.swift prototype/Core/FaceTemplateSet.swift prototype/App/FaceObservationSource.swift \
  prototype/App/FaceEmbedder.swift prototype/App/FaceVisionFallback.swift tests/FaceScanChallengeFlowTests.swift \
  -framework AVFoundation -framework Vision -framework CoreVideo \
  -o .build/face-scan-challenge-flow-tests/flow
.build/face-scan-challenge-flow-tests/flow
