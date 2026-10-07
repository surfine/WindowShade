#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-observation-sharing-tests/module-cache
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path .build/face-observation-sharing-tests/module-cache \
  prototype/App/FaceObservationSource.swift prototype/App/FaceVisionFallback.swift \
  tests/FaceObservationSharingTests.swift \
  -framework AVFoundation -framework Vision -framework CoreVideo \
  -o .build/face-observation-sharing-tests/sharing
.build/face-observation-sharing-tests/sharing
