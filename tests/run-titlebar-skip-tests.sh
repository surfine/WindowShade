#!/bin/bash
# #39：修饰键出口（按住 Option 等修饰键的多击不收起、清三击意图）纯逻辑测试。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/titlebar-skip-tests
swiftc -parse-as-library -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/App/TapDecision.swift \
  tests/TitlebarModifierSkipTests.swift \
  -o .build/titlebar-skip-tests/titlebar-skip
.build/titlebar-skip-tests/titlebar-skip
