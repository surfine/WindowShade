#!/bin/bash
# 刷脸实验接线（IDWIRE）：否决线索、画质门、次数、证据进账本（纯逻辑），和相机队列上的画质采样（合成像素）。
# 只加门槛、只数次数，不放行、不接系统解锁；不开相机、不跑 Vision、不用 Touch ID。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-scan-screening-tests/module-cache
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/SessionLockState.swift prototype/Core/AuthorizationModels.swift prototype/Core/IdentityEvidence.swift \
  prototype/Core/AuthorizationLedger.swift prototype/Core/FaceCaptureQuality.swift prototype/Core/FaceLivenessCues.swift \
  prototype/Core/FaceIdentityAttempts.swift prototype/Core/FaceScanGuard.swift prototype/Core/FaceScanScreening.swift \
  tests/FaceScanScreeningTests.swift -o .build/face-scan-screening-tests/screening
.build/face-scan-screening-tests/screening
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path .build/face-scan-screening-tests/module-cache \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/App/FaceObservationSource.swift prototype/App/FaceEmbedder.swift prototype/App/FaceVisionFallback.swift \
  prototype/Core/FaceCaptureQuality.swift prototype/Core/FaceLivenessCues.swift tests/FaceRegionPixelsTests.swift \
  -framework AVFoundation -framework Vision -framework CoreVideo \
  -o .build/face-scan-screening-tests/pixels
.build/face-scan-screening-tests/pixels
