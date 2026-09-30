#!/bin/bash
# 设计系统 §6-5：动效令牌的对照测试（数值和收拢之前逐字相等，见 MotionTokensTests.swift）。
# 用法：bash tests/run-motion-tokens-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/motion-tokens-tests
swiftc -parse-as-library prototype/App/Motion.swift prototype/Core/FlickMotion.swift tests/MotionTokensTests.swift \
  -o .build/motion-tokens-tests/tokens
.build/motion-tokens-tests/tokens
