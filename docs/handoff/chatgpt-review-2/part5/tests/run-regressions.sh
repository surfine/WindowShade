#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:?Usage: run-regressions.sh /v5/candidate-repo /combined-handoff-with-part1-and-part4}"
HISTORY="${2:?Supply the combined handoff directory}"
BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
mkdir -p "$BUILD/results"
FLAGS=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors)
swiftc "${FLAGS[@]}" "$BASE/prototype/Core/Contracts.swift" "$BASE/prototype/Core/CodexWire.swift" \
 "$BASE/prototype/Core/FocusTimer.swift" "$BASE/prototype/Core/WS2CompanionFrame.swift" \
 "$BASE/prototype/Core/WS2ApprovalReview.swift" "$BASE/prototype/Core/WS2DeviceInputGate.swift" \
 "$BASE/prototype/Core/WS2FocusWindowOwnership.swift" "$HISTORY/part4/tests/CoreTests.swift" -o "$BUILD/part4"
"$BUILD/part4" "$BUILD/results"
swiftc "${FLAGS[@]}" -parse-as-library "$BASE/prototype/Core/Contracts.swift" \
 "$BASE/prototype/Core/FocusTimer.swift" "$HISTORY/part1/tests/support/WS2TestSupport.swift" \
 "$HISTORY/part1/packages/T1/tests/FocusTimerTests.swift" -o "$BUILD/t1"
"$BUILD/t1"
swiftc "${FLAGS[@]}" -parse-as-library "$BASE/prototype/Core/ConductorGesture.swift" \
 "$BASE/tests/ConductorGestureTests.swift" -o "$BUILD/gesture"
"$BUILD/gesture"
