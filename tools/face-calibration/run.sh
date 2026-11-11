#!/usr/bin/env bash
# 构建并运行刷脸门槛标定工具：  tools/face-calibration/run.sh self-test | embed ... | calibrate ...
# 编译的是 App 里同一份特征管线（FaceEmbedder / VisionFaceEmbedder / FaceScanGuard）和 Core 的标定数学。
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BUILD="$ROOT/.build/face-calibration"
mkdir -p "$BUILD"
if [ "$(uname -s)" != Darwin ]; then echo 'Requires macOS' >&2; exit 3; fi
swiftc -parse-as-library -swift-version 5 -O -o "$BUILD/face-calibration" \
  "$ROOT/tools/face-calibration/FaceCalibration.swift" \
  "$ROOT/prototype/App/FaceEmbedder.swift" "$ROOT/prototype/App/VisionFaceEmbedder.swift" "$ROOT/prototype/App/FaceEmbedderBackends.swift" \
  "$ROOT/prototype/Core/FaceScanGuard.swift" "$ROOT/prototype/Core/SessionLockState.swift" \
  "$ROOT/prototype/Core/FaceTemplateSet.swift" "$ROOT/prototype/Core/FaceThresholdCalibration.swift" "$ROOT/prototype/Core/GazeAttention.swift" \
  -framework Foundation -framework Accelerate -framework AVFoundation -framework CoreImage -framework CoreVideo -framework ImageIO -framework Vision
exec "$BUILD/face-calibration" "$@"
