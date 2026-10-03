#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES=()
if [[ -f "$ROOT/prototype/Core/Contracts.swift" ]]; then
  SOURCES+=("$ROOT/prototype/Core/Contracts.swift")
  SUPPORT="$ROOT/tests/support/WS2TestSupport.swift"
  SOURCES+=("$ROOT/prototype/Core/InputDeviceKind.swift")
else
  BUNDLE="$(cd "$ROOT/../.." && pwd)"
  SOURCES+=("$BUNDLE/contracts/Contracts.swift")
  SUPPORT="$BUNDLE/tests/support/WS2TestSupport.swift"
  SOURCES+=("$BUNDLE/packages/I1b/prototype/Core/InputDeviceKind.swift")
fi
BUILD="$ROOT/.build/input-device-kind"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "${SOURCES[@]}" "$SUPPORT" "$ROOT/tests/InputDeviceKindTests.swift" -o "$BUILD/input-device-kind-tests"
"$BUILD/input-device-kind-tests"
