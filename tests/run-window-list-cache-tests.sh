#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/window-list-tests
swiftc prototype/Window/WindowListCache.swift tests/WindowListCacheTests.swift -o .build/window-list-tests/tests
.build/window-list-tests/tests
