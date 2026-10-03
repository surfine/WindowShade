#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
mkdir -p "$ROOT/.build/privacy"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
 "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/contracts/Contracts.swift" \
 "$HERE/SecureLogFile.swift" "$HERE/SecureLogFileTests.swift" -o "$ROOT/.build/privacy/tests"
"$ROOT/.build/privacy/tests"
