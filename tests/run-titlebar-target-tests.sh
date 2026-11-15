#!/bin/bash
# 标题栏目标的通用规则：非一般 App 的非第 0 层或非标准窗口不是目标。
# 纯判定，不开窗口、不读辅助功能、不需要授权。
# 用法：bash tests/run-titlebar-target-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/titlebar-target-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Compatibility/TitlebarTargetPolicy.swift \
  tests/TitlebarTargetPolicyTests.swift \
  -o .build/titlebar-target-tests/titlebar-target
.build/titlebar-target-tests/titlebar-target
