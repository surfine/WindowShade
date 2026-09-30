#!/bin/bash
# 时序特征聚合：纯逻辑，只把按键/指针压成数值特征，不听系统、不碰用户状态。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/behavior-tests/features
swiftc -parse-as-library tools/behavior-lab/TimingFeatures.swift tests/TimingFeaturesTests.swift \
  -o .build/behavior-tests/features/features
.build/behavior-tests/features/features
