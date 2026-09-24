#!/bin/bash
# 看一眼：指针意图状态机（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/glance-tests
swiftc prototype/Core/GlanceIntent.swift tests/GlanceIntentTests.swift -o .build/glance-tests/intent
.build/glance-tests/intent
