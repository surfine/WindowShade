#!/bin/bash
# 多前置镜头的纯逻辑。不编进 run-silent-prep-tests.sh。
# 用法：bash tests/run-camera-choice-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/camera-choice-tests
swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/WS2CameraChoice.swift
swiftc -parse-as-library -swift-version 6 -warnings-as-errors \
  prototype/Core/WS2CameraChoice.swift tests/CameraChoiceTests.swift \
  -o .build/camera-choice-tests/camera-choice
.build/camera-choice-tests/camera-choice
