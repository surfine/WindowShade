#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/carplay-tests
swiftc -module-cache-path "$PWD/.build/module-cache" \
  prototype/Core/WS2CarPlaySession.swift tests/WS2CarPlaySessionTests.swift \
  -o .build/carplay-tests/session
.build/carplay-tests/session
