#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
BASE=tools/probes/companion-pairing
OUT=.build/remote-device-probe
OPENSSL_PREFIX=${WS_SRP_OPENSSL_PREFIX:-/opt/homebrew/opt/openssl@3}
mkdir -p "$OUT/module-cache"
python3 tools/probes/remote-device/build-manifest.py begin
clang -std=c11 -Wall -Wextra -Werror -O2 -I"$OPENSSL_PREFIX/include" -c "$BASE/WSNativeSRP.c" -o "$OUT/WSNativeSRP.o"
xcrun swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -DWS2_PROBE_DIAGNOSTICS -parse-as-library \
  -module-cache-path "$OUT/module-cache" -I "$BASE" \
  prototype/Core/Contracts.swift prototype/Core/PairingTLV.swift prototype/Core/PairingAttemptWindow.swift \
  prototype/Core/WS2OPACK.swift prototype/Core/WS2CompanionFrame.swift prototype/Core/WS2BoundedOutbox.swift \
  prototype/Support/WS2PeerRepository.swift prototype/Support/WS2PairSetupServer.swift \
  prototype/Support/WS2PureSRP.swift prototype/Support/WS2PairSetupCrypto.swift prototype/Support/WS2CompanionPairSetupChannel.swift \
  prototype/Support/WS2CompanionCrypto.swift prototype/Support/WS2CompanionChannel.swift \
  prototype/Support/WS2CompanionTCPTransport.swift "$BASE/WS2NativeSRPPrimitive.swift" \
  tools/probes/remote-device/Handshake.swift tools/probes/remote-device/WireTest.swift tools/probes/remote-device/DiscoveryProfile.swift tools/probes/remote-device/SessionProfile.swift tools/probes/remote-device/OfflineTests.swift \
  tools/probes/remote-device/ProbeConfiguration.swift tools/probes/remote-device/NativeLoopback.swift \
  tools/probes/remote-device/RemoteDeviceProbe.swift "$OUT/WSNativeSRP.o" \
  -L"$OPENSSL_PREFIX/lib" -lcrypto -o "$OUT/RemoteDeviceProbe"
python3 tools/probes/remote-device/build-manifest.py finish
if [[ "${1:-}" == "--build-only" && "$#" == 1 ]]; then exit 0; fi
exec "$OUT/RemoteDeviceProbe" "$@"
