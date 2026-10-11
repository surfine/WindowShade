#!/bin/bash
# iAP2 探针离线测试：CSM、链路、MFi 身份（现场生成自签测试材料，不碰蓝牙）。
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/carplay-tests
swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path "$PWD/.build/module-cache" \
  tools/carplay/iap2/Iap2Csm.swift tools/carplay/iap2/Iap2Link.swift \
  tools/carplay/iap2/Iap2MfiIdentity.swift tools/carplay/iap2/OfflineTests.swift \
  -framework Security \
  -o .build/carplay-tests/iap2-offline
.build/carplay-tests/iap2-offline
