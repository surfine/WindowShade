#!/usr/bin/env bash
# 离开就锁（R07B）：折叠→锁时间表与解锁后只放回自己收的窗口。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/presence-tuck-ledger"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/SessionLockState.swift" \
  "$ROOT/prototype/Core/PresenceLock.swift" "$ROOT/prototype/Core/PresenceLockGlue.swift" \
  "$ROOT/prototype/Core/BystanderPolicy.swift" "$ROOT/prototype/Core/PresenceTuckLedger.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/PresenceTuckLedgerTests.swift" \
  -o "$BUILD/presence-tuck-ledger-tests"
"$BUILD/presence-tuck-ledger-tests"
