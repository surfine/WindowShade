#!/bin/bash
# 规格 E3（改做法）卡顿表的纯计算测试。用法：bash tests/run-hitch-meter-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/hitch-meter-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Core/HitchMeter.swift tests/HitchMeterTests.swift \
  -o .build/hitch-meter-tests/hitch
.build/hitch-meter-tests/hitch
