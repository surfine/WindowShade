#!/bin/bash
# 接收器线协议与 Annex B 转换（纯字节，不碰网络、不启动接收器）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/carplay-tests
swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path "$PWD/.build/module-cache" \
  prototype/Core/WSL10n.swift prototype/Support/WS2CarPlayReceiverWire.swift prototype/Support/WS2CarPlayVideoDecoder.swift \
  tests/WS2CarPlayReceiverWireTests.swift \
  -framework AppKit -framework AVFoundation -framework CoreMedia -framework VideoToolbox \
  -o .build/carplay-tests/receiver-wire
.build/carplay-tests/receiver-wire
