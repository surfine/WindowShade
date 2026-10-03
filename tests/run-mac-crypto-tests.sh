#!/usr/bin/env bash
# 第四份的 CryptoKit 执行测试：按 Python 参考向量核 Mac 侧的握手与记录加密。
# 没有向量文件或不在 Mac 上时明确失败，不用语法检查冒充。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/mac-crypto"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/PairingTLV.swift" \
  "$ROOT/prototype/Core/WS2CompanionFrame.swift" \
  "$ROOT/prototype/Support/WS2CompanionCrypto.swift" \
  "$ROOT/tests/MacCryptoTests.swift" -o "$OUT/mac-crypto"
"$OUT/mac-crypto" "$ROOT/tests/fixtures/companion-crypto-vectors.json"
