#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then echo 'NOT RUN: requires macOS CryptoKit; exit 78'; exit 78; fi
BASE="${1:?Usage: run-mac-crypto.sh /path/to/candidate-repo}"
BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
 "$BASE/prototype/Core/PairingTLV.swift" "$BASE/prototype/Core/PairingAttemptWindow.swift" \
 "$ROOT/overlay/prototype/Support/WS2PeerRepository.swift" \
 "$ROOT/overlay/prototype/Support/WS2PairSetupServer.swift" \
 "$ROOT/overlay/prototype/Support/WS2PairSetupCrypto.swift" "$ROOT/tests/MacPairCryptoTests.swift" -o "$BUILD/mac-pair"
"$BUILD/mac-pair" "$ROOT/reference/pair-setup-vectors.json"
