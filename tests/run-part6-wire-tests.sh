#!/usr/bin/env bash
# 第六份 Wire profile：只读/人工审批/分页参数，以及按钉住 schema 的核验。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/part6-wire"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/CodexWire.swift" \
  "$ROOT/prototype/Core/WS2StrictJSON.swift" \
  "$ROOT/tests/WireProfileTests.swift" -o "$OUT/wire-tests"
"$OUT/wire-tests" "$OUT/wire-results.json" "$OUT/wire-outbound.ndjson"
if python3 -c 'import jsonschema' 2>/dev/null; then
  python3 "$ROOT/tests/check-wire-schema.py" "$ROOT" "$OUT/wire-outbound.ndjson" "$OUT/wire-schema.json"
else
  node "$ROOT/tests/check-wire-schema.mjs" "$ROOT" "$OUT/wire-outbound.ndjson" "$OUT/wire-schema.json"
fi
