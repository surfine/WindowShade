#!/bin/bash
# 编译 iAP2/MFi 探针（隔离工具，不进 App；真机运行需要终端蓝牙权限与用户自备身份目录）。
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/carplay-tests
swiftc -O -swift-version 6 -strict-concurrency=complete \
  -module-cache-path "$PWD/.build/module-cache" \
  tools/carplay/iap2/Iap2Csm.swift tools/carplay/iap2/Iap2Link.swift \
  tools/carplay/iap2/Iap2MfiIdentity.swift tools/carplay/iap2/main.swift \
  -framework IOBluetooth -framework Security \
  -o .build/carplay-tests/iap2-probe
echo "built: .build/carplay-tests/iap2-probe"
echo "usage: .build/carplay-tests/iap2-probe --identity-dir <dir> --address <BT addr> [--seconds 60]"
