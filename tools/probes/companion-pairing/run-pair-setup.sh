#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
BASE=tools/probes/companion-pairing
OUT=.build/native-srp-probe
OPENSSL_PREFIX=${WS_SRP_OPENSSL_PREFIX:-/opt/homebrew/opt/openssl@3}
mkdir -p "$OUT/module-cache"
clang -std=c11 -Wall -Wextra -Werror -O2 -I"$OPENSSL_PREFIX/include" -c "$BASE/WSNativeSRP.c" -o "$OUT/WSNativeSRP.o"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path "$OUT/module-cache" -I "$BASE" \
  prototype/Core/Contracts.swift prototype/Core/PairingTLV.swift prototype/Core/PairingAttemptWindow.swift \
  prototype/Core/WS2OPACK.swift prototype/Core/WS2CompanionFrame.swift prototype/Core/WS2BoundedOutbox.swift \
  prototype/Support/WS2PeerRepository.swift prototype/Support/WS2PairSetupServer.swift \
  prototype/Support/WS2PairSetupCrypto.swift prototype/Support/WS2CompanionPairSetupChannel.swift \
  prototype/Support/WS2CompanionCrypto.swift prototype/Support/WS2CompanionChannel.swift \
  prototype/Support/WS2CompanionTCPTransport.swift \
  "$BASE/WS2NativeSRPPrimitive.swift" "$BASE/PairSetupProbe.swift" \
  "$OUT/WSNativeSRP.o" -L"$OPENSSL_PREFIX/lib" -lcrypto -o "$OUT/pair-setup-probe"
echo "Compiled isolated M1-M6 integration probe (NOT DISTRIBUTABLE; no sockets opened)"
