#!/usr/bin/env bash
# 录脸「确认才写」端到端：合成帧 + 真授权账 + 测试钥匙串条目。不碰用户的钥匙串，不开相机。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-enrollment-save-roundtrip
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/SessionLockState.swift \
  prototype/Core/AuthorizationModels.swift prototype/Core/IdentityEvidence.swift prototype/Core/AuthorizationLedger.swift \
  prototype/Core/FaceCaptureQuality.swift prototype/Core/FaceScanGuard.swift prototype/Core/FaceTemplateSet.swift \
  prototype/Core/FaceEnrollmentFlow.swift \
  prototype/App/FaceTemplateKeychainStore.swift \
  tests/FaceEnrollmentSaveRoundTripTests.swift \
  -o .build/face-enrollment-save-roundtrip/run
.build/face-enrollment-save-roundtrip/run
