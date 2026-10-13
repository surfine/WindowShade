#!/bin/bash
# 画质门与认出你的次数（纯逻辑；只加门槛、只数次数，不放行、不接系统解锁）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-quality-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/FaceCaptureQuality.swift tests/FaceCaptureQualityTests.swift -o .build/face-quality-tests/quality
.build/face-quality-tests/quality
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/FaceCaptureQuality.swift prototype/Core/FaceIdentityAttempts.swift tests/FaceIdentityAttemptsTests.swift \
  -o .build/face-quality-tests/attempts
.build/face-quality-tests/attempts
