#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:?Usage: run-exit-probe.sh /v5-or-v6/candidate-repo}"
BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
 "$BASE/prototype/Core/WS2BoundedOutbox.swift" "$ROOT/overlay/prototype/Core/WS2DiagnosticTail.swift" \
 "$ROOT/overlay/prototype/Support/WS2DuplexProcess.swift" "$ROOT/tests/ExitInheritanceProbe.swift" -o "$BUILD/probe"
"$BUILD/probe" "$ROOT/tests/child.py" "${2:-$ROOT/validation/exit-inheritance-probe.json}"
