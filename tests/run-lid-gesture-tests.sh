#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/lid-gesture-tests
swiftc -parse-as-library prototype/Core/LidGesture.swift tests/LidGestureTests.swift -o .build/lid-gesture-tests/gesture
.build/lid-gesture-tests/gesture
