#!/usr/bin/env bash
# 三／四指读取桥：符号与 ABI 候选、资格门禁（未核对永远不装）。不注册回调、不启动设备。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/multitouch-bridge"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/MultitouchQualification.swift" \
  "$ROOT/prototype/Core/InputFeatureGate.swift" \
  "$ROOT/prototype/Private/MultitouchBridge.swift" \
  "$ROOT/tests/MultitouchBridgeTests.swift" \
  -o "$BUILD/multitouch-bridge-tests"
"$BUILD/multitouch-bridge-tests" "$@"
