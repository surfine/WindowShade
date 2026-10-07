#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/companion-channel"
mkdir -p "$OUT/module-cache"
swiftc -module-cache-path "$OUT/module-cache" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" "$ROOT/prototype/Core/PairingTLV.swift" \
  "$ROOT/prototype/Core/WS2CompanionFrame.swift" "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Core/WS2OPACK.swift" "$ROOT/prototype/Support/WS2CompanionCrypto.swift" \
  "$ROOT/prototype/Support/WS2CompanionTCPTransport.swift" "$ROOT/prototype/Support/WS2CompanionChannel.swift" \
  "$ROOT/tests/CompanionChannelTests.swift" -o "$OUT/companion-channel"
cd "$ROOT"
"$OUT/companion-channel" "${1:---offline-tests}"
