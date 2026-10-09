#!/bin/bash
# 刷脸被动线索纯逻辑（只否决不放行，不开相机）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-liveness-cues-tests
swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors prototype/Core/FaceLivenessCues.swift
swiftc -swift-version 6 -parse-as-library -warnings-as-errors \
  prototype/Core/FaceLivenessCues.swift tests/FaceLivenessCuesTests.swift \
  -o .build/face-liveness-cues-tests/cues
.build/face-liveness-cues-tests/cues
