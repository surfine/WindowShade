#!/usr/bin/env bash
# 第 1 份合同的构建门禁：新增的读取点必须先登记到 tools/privacy/registry.json，
# 没登记就让检查失败。词法检查不是污点分析，只挡“悄悄多读一处”这件事。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tools/privacy/check-registry.py" --repo "$ROOT"
