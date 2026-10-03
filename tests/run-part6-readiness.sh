#!/usr/bin/env bash
# 证据门禁：在隔离副本（不含 .git/.build/node_modules）上按交付清单核证据完整性。
# 现状预期 BLOCKED（exit 2）：真机与设备证据还没补齐。这里如实返回工具的退出码。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "$ROOT/.build/readiness.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# 只要源码候选：排除本地工作树、构建产物、依赖与签名配置（它们不属于交付清单）。
rsync -a --exclude=.git --exclude=.build --exclude=.claude --exclude=.ai-bridge \
      --exclude=.jspace --exclude=.swift-module-cache --exclude=.wrangler \
      --exclude=node_modules --exclude='*.app' --exclude=local-codesign.env \
      --exclude=Topit --exclude=video --exclude=prototype/Vendor "$ROOT/" "$WORK/candidate/"
set +e
python3 "$ROOT/tools/readiness.py" --input "$ROOT/tests/fixtures/readiness-current.json" \
  --evidence-root "$ROOT" --candidate "$WORK/candidate" --report "$WORK/readiness.json"
code=$?
set -e
echo "readiness exit=$code (2 = BLOCKED, the expected state until device and Mac evidence exist)"
exit $code
