#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then echo 'NOT RUN: requires macOS CryptoKit' >&2; exit 78; fi
mkdir -p .build validation
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
 reference/prototype/Core/Contracts.swift reference/prototype/Core/PairingTLV.swift \
 overlay/prototype/Core/WS2CompanionFrame.swift overlay/prototype/Support/WS2CompanionCrypto.swift \
 tests/MacCryptoTests.swift -o .build/mac-crypto
.build/mac-crypto fixtures/companion-crypto-vectors.json | tee validation/mac-crypto.txt
