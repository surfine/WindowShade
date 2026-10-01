#!/bin/bash
# 面部动作检测（眨眼、点头、转头）的时序规则。只是动作，不是身份、注视或活体。此前没有 runner。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-gesture-tracker-tests
swiftc -parse-as-library prototype/Core/FaceGestureTracker.swift prototype/App/FaceObservationSource.swift \
  tests/FaceGestureTrackerTests.swift -framework AVFoundation -framework Vision \
  -o .build/face-gesture-tracker-tests/tracker
.build/face-gesture-tracker-tests/tracker
