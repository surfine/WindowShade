#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES=()
if [[ -f "$ROOT/prototype/Core/Contracts.swift" ]]; then
  SOURCES+=("$ROOT/prototype/Core/Contracts.swift")
  SUPPORT="$ROOT/tests/support/WS2TestSupport.swift"
  SOURCES+=("$ROOT/prototype/Core/ConductorSession.swift")
  SOURCES+=("$ROOT/prototype/Core/ConductorCapabilities.swift")
  SOURCES+=("$ROOT/prototype/Core/ConductorGesture.swift")
else
  BUNDLE="$(cd "$ROOT/../.." && pwd)"
  SOURCES+=("$BUNDLE/contracts/Contracts.swift")
  SUPPORT="$BUNDLE/tests/support/WS2TestSupport.swift"
  SOURCES+=("$BUNDLE/packages/D1/prototype/Core/ConductorSession.swift")
  SOURCES+=("$BUNDLE/packages/D2/prototype/Core/ConductorCapabilities.swift")
  SOURCES+=("$BUNDLE/baseline/ConductorGesture.swift")
fi
BUILD="$ROOT/.build/conductor-session"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "${SOURCES[@]}" "$SUPPORT" "$ROOT/tests/ConductorSessionTests.swift" -o "$BUILD/conductor-session-tests"
"$BUILD/conductor-session-tests"
