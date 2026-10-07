#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/mouth-recording-tests/module-cache
swiftc -D MOUTH_RECORDING_TESTS -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path .build/mouth-recording-tests/module-cache \
  prototype/App/FaceObservationSource.swift prototype/App/FaceVisionFallback.swift \
  prototype/Core/WS2SilentCatalog.swift prototype/Core/WS2SilentPhrases.swift prototype/Core/WS2MouthTemplates.swift \
  tools/probes/MouthRecordingProbe.swift tests/MouthRecordingProbeTests.swift \
  -framework AVFoundation -framework Vision -framework CoreVideo -o .build/mouth-recording-tests/recording
.build/mouth-recording-tests/recording
