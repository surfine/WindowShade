#!/usr/bin/env bash
# 决定 74：锁屏时 iPhone 那条 Pair-Verify 连线当第二道的纯规则——时限、挑战绑这次锁屏与随机数、只答一次、核对窗口、锁着时拒绝一切命令。
# 再加静态门：开关关着时 WS2RemoteHost 锁屏照旧全断（lockVerifyEnabled 默认 false）；拒绝日志只记类别。
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL $*" >&2; exit 1; }
OUT=.build/companion-lock-verify-tests
mkdir -p "$OUT"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/Contracts.swift prototype/Core/CompanionLockVerify.swift \
  tests/support/WS2TestSupport.swift tests/CompanionLockVerifyTests.swift -o "$OUT/lock-verify"
"$OUT/lock-verify"

rg -q "private\(set\) var lockVerifyEnabled = false" prototype/App/WS2RemoteHost.swift || fail "lock verify is not off by default"
rg -q "if lockVerifyEnabled \{ holdForLockVerify\(\) \} else \{ closeAll\(silently: true\) \}" prototype/App/WS2RemoteHost.swift \
  || fail "lock no longer closes everything when lock verify is off"
! rg -n 'record\("lock-verify.*\\\((peer|identifier|name|content|plain|fields|method)' prototype/App/WS2RemoteHost.swift \
  || fail "a lock-verify log line interpolates device or message content"
echo "PASS companion-lock-verify static gates"
