#!/bin/bash
# 指挥页快照：稳定会话身份、代次复核、未完成输入保留草稿。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/conductor-page-tests
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  prototype/Core/Contracts.swift \
  prototype/Core/ConductorPageSnapshot.swift \
  tests/ConductorPageTests.swift \
  -o .build/conductor-page-tests/conductor-page
.build/conductor-page-tests/conductor-page
