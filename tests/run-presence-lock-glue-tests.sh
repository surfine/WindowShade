#!/usr/bin/env bash
# 离开就锁 App 驱动的纯胶水（2-7）：效果→动作、锁态读数→事件、倒数时的输入检查、离开期间记录。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/presence-lock-glue"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/SessionLockState.swift" \
  "$ROOT/prototype/Core/PresenceLock.swift" "$ROOT/prototype/Core/PresenceLockGlue.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/PresenceLockGlueTests.swift" \
  -o "$BUILD/presence-lock-glue-tests"
"$BUILD/presence-lock-glue-tests"
