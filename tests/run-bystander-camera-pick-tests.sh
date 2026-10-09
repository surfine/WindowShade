#!/bin/bash
# 旁人一瞥选镜头的纯逻辑：环境变量覆盖、开关、多镜头。不开相机。
# 用法：bash tests/run-bystander-camera-pick-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/bystander-camera-pick-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/WS2CameraChoice.swift prototype/Core/BystanderCameraPick.swift tests/BystanderCameraPickTests.swift \
  -o .build/bystander-camera-pick-tests/pick
.build/bystander-camera-pick-tests/pick
