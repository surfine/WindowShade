#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/contracts"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
 "$ROOT/contracts/Contracts.swift" "$ROOT/tests/support/WS2TestSupport.swift" \
 "$ROOT/tests/ContractsTests.swift" -o "$ROOT/.build/contracts/tests"
"$ROOT/.build/contracts/tests"
