#!/bin/bash
# 卷轴维护按事件做之后的纯判定：被拖走、被忙碌盖住时的复查、新窗口资格与重试节奏。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/strip-watch-policy-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/StripWatchPolicy.swift tests/StripWatchPolicyTests.swift \
  -o .build/strip-watch-policy-tests/tests
.build/strip-watch-policy-tests/tests
