#!/bin/bash
# R08：刘海小行为的纯判定与时序常量（不需要图形会话）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-small-behaviour-tests
swiftc -parse-as-library -O \
  prototype/Core/CarryShelfLayout.swift \
  tests/NotchSmallBehaviourTests.swift \
  -o .build/notch-small-behaviour-tests/tests
.build/notch-small-behaviour-tests/tests
