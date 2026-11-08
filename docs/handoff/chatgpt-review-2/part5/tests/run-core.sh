#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:?Usage: tests/run-core.sh /path/to/v4-or-v5/candidate-repo}"
BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
 "$BASE/prototype/Core/Contracts.swift" "$BASE/prototype/Core/WS2FocusWindowOwnership.swift" \
 "$BASE/prototype/Core/WS2DeviceInputGate.swift" "$BASE/prototype/Core/PairingAttemptWindow.swift" "$BASE/prototype/Core/PairingTLV.swift" \
 "$ROOT"/overlay/prototype/Core/*.swift "$ROOT/overlay/prototype/Support/WS2PeerRepository.swift" \
 "$ROOT/overlay/prototype/Support/WS2PairSetupServer.swift" "$ROOT/tests/CoreTests.swift" -o "$BUILD/core"
"$BUILD/core" "$ROOT/validation/core-results.json"
