#!/bin/bash
# F12：人脸观察流水线的请求复用与退路重建。纯逻辑，不碰相机硬件。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-pipeline-tests/module-cache
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path .build/face-pipeline-tests/module-cache \
  prototype/App/FaceObservationSource.swift prototype/App/FaceEmbedder.swift prototype/App/FaceVisionFallback.swift \
  tests/FaceObservationPipelineTests.swift \
  -framework AVFoundation -framework Vision -framework CoreVideo \
  -o .build/face-pipeline-tests/pipeline
.build/face-pipeline-tests/pipeline
