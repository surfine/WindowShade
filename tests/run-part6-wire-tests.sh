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
# schema 核验需要 Python 的 jsonschema。系统 Python 受 Homebrew 保护（PEP 668），装不进去时用门禁 venv：
#   python3 -m venv .build/gate-venv && .build/gate-venv/bin/pip install jsonschema
#   export WINDOWSHADE_GATE_PYTHON="$PWD/.build/gate-venv/bin/python3"
# 没设 WINDOWSHADE_GATE_PYTHON 时，若仓库里有 .build/gate-venv 就用它，否则用 python3。
if [ -n "${WINDOWSHADE_GATE_PYTHON:-}" ]; then
  PY="$WINDOWSHADE_GATE_PYTHON"
elif [ -x "$ROOT/.build/gate-venv/bin/python3" ]; then
  PY="$ROOT/.build/gate-venv/bin/python3"
else
  PY=python3
fi
if ! "$PY" -c 'import jsonschema' 2>/dev/null; then
  echo "FAIL wire-schema: ${PY} 里没有 jsonschema，钉住的 schema 没有被核对。" >&2
  echo "  创建门禁 venv：python3 -m venv .build/gate-venv && .build/gate-venv/bin/pip install jsonschema" >&2
  echo "  或把 WINDOWSHADE_GATE_PYTHON 指向装有 jsonschema 的 python3。" >&2
  exit 1
fi
"$PY" "$ROOT/tests/check-wire-schema.py" "$ROOT" "$OUT/wire-outbound.ndjson" "$OUT/wire-schema.json"
