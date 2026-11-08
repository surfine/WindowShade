#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
 "$ROOT/overlay/prototype/Core/WS2BoundedOutbox.swift" \
 "$ROOT/overlay/prototype/Support/WS2DuplexProcess.swift" "$ROOT/tests/ProcessTests.swift" -o "$BUILD/process"
"$BUILD/process" "$ROOT/tests/fake-child.py" "$ROOT/validation/process-results.json"
