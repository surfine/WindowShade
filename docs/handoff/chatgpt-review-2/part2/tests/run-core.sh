set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors "$ROOT/contracts/Contracts.swift" "$ROOT/contracts/InteractionCoordinator.swift" "$ROOT/packages/D6/prototype/Core/CodexWire.swift" "$ROOT/packages/D5a/prototype/Core/RemoteSessionGate.swift" "$ROOT/packages/L2/prototype/Core/PresenceReadDeadline.swift" "$ROOT/tests/Part2CoreTests.swift" -o "$BUILD/test"
"$BUILD/test" "$ROOT/validation/codex-outbound.ndjson"
