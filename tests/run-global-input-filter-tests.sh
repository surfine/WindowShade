#!/bin/bash
# 合成输入监听：过滤谓词和各处理函数 guard 的对照表、输入线程的账、快照更新、退回 NSEvent 监听。
# 最后一项会试着建一个真的 listen-only tap 并发一个“指针原地移动”；没有授权时打印 skip，不算失败。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/global-input-filter-tests
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  prototype/Support/SecureLogFile.swift \
  prototype/Support/Diagnostics.swift \
  prototype/Window/Coordinates.swift \
  prototype/Core/DockLockRule.swift \
  prototype/WindowBrowser/WindowBrowserDockDetection.swift \
  prototype/App/GlobalInputFilter.swift \
  tests/GlobalInputFilterTests.swift \
  -o .build/global-input-filter-tests/tests
.build/global-input-filter-tests/tests
