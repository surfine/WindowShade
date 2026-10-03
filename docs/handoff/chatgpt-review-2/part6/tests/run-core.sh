#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:?Usage: run-core.sh /v5-or-v6/candidate-repo}"
BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
 "$BASE/prototype/Core/Contracts.swift" "$ROOT/overlay/prototype/App/InteractionCoordinator.swift" \
 "$ROOT/overlay/prototype/Core/WS2DiagnosticTail.swift" "$ROOT/overlay/prototype/Core/WS2OwnedScope.swift" \
 "$ROOT/overlay/prototype/Support/WS2ProjectDirectory.swift" "$ROOT/overlay/prototype/Core/WS2SelectionModel.swift" \
 "$ROOT/overlay/prototype/Core/WS2ConnectionBudget.swift" "$ROOT/tests/CoreTests.swift" -o "$BUILD/core"
"$BUILD/core" "${2:-$ROOT/validation/core-results.json}"
