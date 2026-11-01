#!/bin/bash
# 双击的第二下：按下被吞后，配对的松开也只吞一次。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/mouse-up-swallow-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Core/MouseUpSwallow.swift \
  tests/MouseUpSwallowTests.swift \
  -o .build/mouse-up-swallow-tests/tests
.build/mouse-up-swallow-tests/tests
