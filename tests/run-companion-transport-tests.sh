#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/companion-transport"
mkdir -p "$OUT/module-cache"
swiftc -module-cache-path "$OUT/module-cache" -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -D WS2_TRANSPORT_TESTING -parse-as-library \
  "$ROOT/prototype/Core/WS2CompanionFrame.swift" "$ROOT/prototype/Core/WS2BoundedOutbox.swift" \
  "$ROOT/prototype/Support/WS2CompanionTCPTransport.swift" "$ROOT/tests/CompanionTransportTests.swift" \
  -o "$OUT/companion-transport"
"$OUT/companion-transport" "${1:---controlled}"
