#!/bin/bash
set -euo pipefail
BASE="${1:?Usage: check-foundation.sh /v5/candidate-repo}"
FILES=()
for name in Contracts WS2FocusWindowOwnership WS2DeviceInputGate PairingAttemptWindow PairingTLV CodexWire WS2CompanionFrame WS2ApprovalReview FocusTimer GamepadMapping WS2BoundedOutbox WS2FocusEffectPlan WS2SemanticInputRouter; do
 FILES+=("$BASE/prototype/Core/$name.swift")
done
for name in WS2PeerRepository WS2PairSetupServer WS2PairSetupCrypto WS2FocusEffectExecutor WS2DuplexProcess; do
 FILES+=("$BASE/prototype/Support/$name.swift")
done
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -typecheck "${FILES[@]}"
