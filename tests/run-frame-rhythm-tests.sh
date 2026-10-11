#!/bin/bash
# MO-07 帧节奏探针的纯计算测试。用法：bash tests/run-frame-rhythm-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/frame-rhythm-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/FrameRhythmAnalysis.swift tests/FrameRhythmAnalysisTests.swift \
  -o .build/frame-rhythm-tests/rhythm
.build/frame-rhythm-tests/rhythm
