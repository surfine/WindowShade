#!/bin/bash
# 运动判定 + 盖角轮询间隔（纯逻辑；静止降频、在动/合盖照旧）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/motion-activity-tests
swiftc -parse-as-library prototype/Core/MotionActivity.swift tests/MotionActivityTests.swift \
  -o .build/motion-activity-tests/activity
.build/motion-activity-tests/activity
