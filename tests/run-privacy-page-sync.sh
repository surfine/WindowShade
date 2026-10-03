#!/usr/bin/env bash
# 隐私页的数据必须和登记表一字不差：重新生成一份，和仓库里的比。改了 registry.json
# 却没重新生成（或反过来手改了生成文件），这里就红。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -t ws2-privacy-XXXXXX).swift"
trap 'rm -f "$OUT"' EXIT
python3 "$ROOT/tools/privacy/make-privacy-page-source.py" --out "$OUT" >/dev/null
if ! diff -q "$OUT" "$ROOT/prototype/App/WS2PrivacyData.swift" >/dev/null; then
  echo "FAIL privacy-page: prototype/App/WS2PrivacyData.swift 与 tools/privacy/registry.json 不一致"
  diff -u "$ROOT/prototype/App/WS2PrivacyData.swift" "$OUT" | head -40
  exit 1
fi
echo "PASS privacy-page: 生成的数据源与登记表一致"
