#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; BASE="${1:?Supply v5 or v6 candidate repo}"
BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors "$BASE/prototype/Core/Contracts.swift" \
 "$ROOT/overlay/prototype/Core/CodexWire.swift" "$ROOT/tests/WireProfileTests.swift" -o "$BUILD/wire"
"$BUILD/wire" "$ROOT/validation/wire-results.json" "$ROOT/validation/wire-outbound.ndjson"
python3 "$ROOT/tests/check-wire-schema.py" "$BASE" "$ROOT/validation/wire-outbound.ndjson" "$ROOT/validation/wire-schema.json"
