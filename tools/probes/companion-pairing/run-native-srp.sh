#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
BASE=tools/probes/companion-pairing
OUT=.build/native-srp-probe
OPENSSL_PREFIX=${WS_SRP_OPENSSL_PREFIX:-/opt/homebrew/opt/openssl@3}
mkdir -p "$OUT/module-cache"
[[ -f "$OPENSSL_PREFIX/include/openssl/bn.h" ]] || { echo 'Set WS_SRP_OPENSSL_PREFIX to a local OpenSSL 3 installation'; exit 78; }
clang -std=c11 -Wall -Wextra -Werror -O2 -I"$OPENSSL_PREFIX/include" \
  -c "$BASE/WSNativeSRP.c" -o "$OUT/WSNativeSRP.o"
# The non-testing object must never export deterministic secret injection hooks.
if nm -g "$OUT/WSNativeSRP.o" | rg -q ws_srp_test_; then echo 'Unexpected test hooks'; exit 2; fi
clang -std=c11 -Wall -Wextra -Werror -O2 -DWS_SRP_TESTING -I"$OPENSSL_PREFIX/include" \
  "$BASE/WSNativeSRP.c" "$BASE/NativeSRPTests.c" -L"$OPENSSL_PREFIX/lib" -lcrypto -o "$OUT/c-tests"
"$OUT/c-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path "$OUT/module-cache" -I "$BASE" \
  prototype/Core/PairingTLV.swift prototype/Core/PairingAttemptWindow.swift \
  prototype/Support/WS2PeerRepository.swift prototype/Support/WS2PairSetupServer.swift \
  prototype/Support/WS2PairSetupCrypto.swift "$BASE/WS2NativeSRPPrimitive.swift" "$BASE/SRPProbe.swift" \
  "$OUT/WSNativeSRP.o" -L"$OPENSSL_PREFIX/lib" -lcrypto -o "$OUT/srp-probe"
echo "Compiled isolated Swift adapter against existing protocols: $OUT/srp-probe (NOT DISTRIBUTABLE)"
