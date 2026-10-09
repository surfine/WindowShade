#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/bounded-wait-tests
swiftc -swift-version 6 prototype/App/WindowGlide.swift prototype/Window/WindowListCache.swift prototype/Core/FlickMotion.swift tests/BoundedWaitTests.swift -o .build/bounded-wait-tests/tests
.build/bounded-wait-tests/tests
