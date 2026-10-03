#!/usr/bin/env bash
# 第五份 CryptoKit 配对分层：M5/M6 签名与 AEAD，按固定向量核。非 Mac 明确 NOT RUN。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then echo 'NOT RUN: requires macOS CryptoKit; exit 78'; exit 78; fi
OUT="$ROOT/.build/part5-mac-pair-crypto"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/PairingTLV.swift" \
  "$ROOT/prototype/Core/PairingAttemptWindow.swift" \
  "$ROOT/prototype/Support/WS2PeerRepository.swift" \
  "$ROOT/prototype/Support/WS2PairSetupServer.swift" \
  "$ROOT/prototype/Support/WS2PairSetupCrypto.swift" \
  "$ROOT/tests/Part5MacPairCryptoTests.swift" -o "$OUT/mac-pair"
"$OUT/mac-pair" "$ROOT/tests/fixtures/pair-setup-vectors.json"
