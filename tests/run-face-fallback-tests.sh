#!/bin/bash
# PERF-07：相机像素格式偏好、Vision 失败类别与一次性 ANE 退路状态机的单元验证。
# 纯逻辑，不碰相机硬体（真机项目写进 runbook，标 not_run）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-fallback-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/App/FaceVisionFallback.swift \
  tests/FaceVisionFallbackTests.swift \
  -framework Vision -framework CoreVideo \
  -o .build/face-fallback-tests/face-fallback
.build/face-fallback-tests/face-fallback
