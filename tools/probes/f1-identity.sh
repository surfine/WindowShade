#!/bin/bash
# F1 身份探针：连已配对的 iPhone/Watch，读需要加密的特性，记录「就是那台手机」的证据。
# --check 只编译自检，不开蓝牙；真跑要真机在场（见 docs/f1-experiment.md）。
set -euo pipefail
cd "$(dirname "$0")/../.."
BUILD=.build/f1-identity
mkdir -p "$BUILD/module-cache"
swiftc -swift-version 6 -warnings-as-errors -parse-as-library \
  -module-cache-path "$BUILD/module-cache" \
  tools/probes/F1IdentityProbe.swift -framework CoreBluetooth -framework Foundation \
  -o "$BUILD/f1-identity"
if [[ "${1:-}" == "--check" ]]; then
  "$BUILD/f1-identity" --check
  echo "compiled; radio not opened"
  exit 0
fi
exec "$BUILD/f1-identity" "$@"
