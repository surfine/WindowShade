#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:?Supply v6 candidate repo}"; HISTORY="${2:?Supply v5 handoff root}"
BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
FLAGS=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors)
FILES=()
for name in Contracts WS2FocusWindowOwnership WS2DeviceInputGate PairingAttemptWindow PairingTLV WS2BoundedOutbox WS2FocusEffectPlan WS2SemanticInputRouter; do FILES+=("$BASE/prototype/Core/$name.swift"); done
swiftc "${FLAGS[@]}" "${FILES[@]}" "$BASE/prototype/Support/WS2PeerRepository.swift" \
 "$BASE/prototype/Support/WS2PairSetupServer.swift" "$HISTORY/part5/tests/CoreTests.swift" -o "$BUILD/p5-core"
"$BUILD/p5-core" "$ROOT/validation/regression-part5-core.json"
swiftc "${FLAGS[@]}" "$BASE/prototype/Core/WS2BoundedOutbox.swift" "$BASE/prototype/Core/WS2DiagnosticTail.swift" \
 "$BASE/prototype/Support/WS2DuplexProcess.swift" "$HISTORY/part5/tests/ProcessTests.swift" -o "$BUILD/p5-process"
"$BUILD/p5-process" "$HISTORY/part5/tests/fake-child.py" "$ROOT/validation/regression-part5-process.json"
swiftc "${FLAGS[@]}" "$BASE/prototype/Core/Contracts.swift" "$BASE/prototype/App/InteractionCoordinator.swift" \
 "$BASE/prototype/Core/CodexWire.swift" "$BASE/prototype/Core/RemoteSessionGate.swift" "$BASE/prototype/Core/PresenceReadDeadline.swift" \
 "$HISTORY/part2/tests/Part2CoreTests.swift" -o "$BUILD/p2"
"$BUILD/p2" "$ROOT/validation/regression-part2-outbound.ndjson"
bash "$HISTORY/part5/tests/run-regressions.sh" "$BASE" "$HISTORY"
