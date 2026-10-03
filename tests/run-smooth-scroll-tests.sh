#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES=()
if [[ -f "$ROOT/prototype/Core/Contracts.swift" ]]; then
  SOURCES+=("$ROOT/prototype/Core/Contracts.swift")
  SUPPORT="$ROOT/tests/support/WS2TestSupport.swift"
  SOURCES+=("$ROOT/prototype/Core/SmoothScroll.swift")
else
  BUNDLE="$(cd "$ROOT/../.." && pwd)"
  SOURCES+=("$BUNDLE/contracts/Contracts.swift")
  SUPPORT="$BUNDLE/tests/support/WS2TestSupport.swift"
  SOURCES+=("$BUNDLE/packages/I1a/prototype/Core/SmoothScroll.swift")
fi
BUILD="$ROOT/.build/smooth-scroll"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "${SOURCES[@]}" "$SUPPORT" "$ROOT/tests/SmoothScrollTests.swift" -o "$BUILD/smooth-scroll-tests"
"$BUILD/smooth-scroll-tests"
