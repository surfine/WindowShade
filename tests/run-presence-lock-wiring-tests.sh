#!/usr/bin/env bash
# 离开就锁的接线（R07）：锁前动作顺序、读屏节点、只续播自己暂停的、windowshade://lock 校验与归属。
# 顺带跑一遍纯胶水的旧测试（命令形状改过）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/presence-lock-wiring"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/SessionLockState.swift" \
  "$ROOT/prototype/Core/PresenceLock.swift" "$ROOT/prototype/Core/PresenceLockGlue.swift" \
  "$ROOT/prototype/Core/WS2AwaySimulation.swift" "$ROOT/prototype/Core/WS2LockRequestPolicy.swift" \
  "$ROOT/prototype/App/WS2URLHandler.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/PresenceLockWiringTests.swift" \
  -o "$BUILD/presence-lock-wiring-tests"
"$BUILD/presence-lock-wiring-tests"
bash "$ROOT/tests/run-presence-lock-glue-tests.sh" | tail -1
