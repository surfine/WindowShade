#!/usr/bin/env bash
# 第六份 Wire profile：只读/人工审批/分页参数，以及按钉住 schema 的核验。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/part6-wire"
mkdir -p "$OUT"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/WireJSON.swift" \
  "$ROOT/prototype/Core/CodexWire.swift" \
  "$ROOT/prototype/Core/WS2StrictJSON.swift" \
  "$ROOT/tests/WireProfileTests.swift" -o "$OUT/wire-tests"
"$OUT/wire-tests" "$OUT/wire-results.json" "$OUT/wire-outbound.ndjson"
# schema 核验要一个 JSON Schema 校验器：python 的 jsonschema 或概念片里带来的 ajv。
# 公开树已不含 film/（bc4bd548 移去私有仓库），两样都没有时明确 SKIP，不红也不假装核过。
if python3 -c 'import jsonschema' 2>/dev/null; then
  python3 "$ROOT/tests/check-wire-schema.py" "$ROOT" "$OUT/wire-outbound.ndjson" "$OUT/wire-schema.json"
elif [ -d "$ROOT/film/ws2-concept/node_modules/ajv" ]; then
  node "$ROOT/tests/check-wire-schema.mjs" "$ROOT" "$OUT/wire-outbound.ndjson" "$OUT/wire-schema.json"
else
  echo "SKIP wire-schema: python jsonschema 与 ajv 都不在（film/ 已移入私有仓库）；Swift 侧 wire 断言已在上面跑过"
fi
