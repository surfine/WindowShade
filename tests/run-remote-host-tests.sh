#!/usr/bin/env bash
# iPhone 上的遥控器接收端（M04）：开关生命周期、Touch ID 回执才登记、单一操作者、锁屏清理、配对码不进日志。
# 不开 socket、不碰钥匙串：连接、监听、存储、刘海都用内存替身；Pair-Verify 用 CryptoKit 走真实握手。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/remote-host"
mkdir -p "$OUT/module-cache"
P="$ROOT/prototype"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -D WS2_REMOTE_HOST_TESTING -module-cache-path "$OUT/module-cache" \
  "$P/Core/Contracts.swift" "$P/Core/WSL10n.swift" "$P/Core/PrivacyPaneName.swift" "$P/Core/PairingTLV.swift" "$P/Core/PairingAttemptWindow.swift" \
  "$P/Core/WS2OPACK.swift" "$P/Core/WS2CompanionFrame.swift" "$P/Core/WS2BoundedOutbox.swift" \
  "$P/Core/WS2ConnectionBudget.swift" "$P/Core/CompanionHIDMap.swift" "$P/Core/RemoteMode.swift" \
  "$P/Core/ConductorSession.swift" "$P/Core/ConductorCapabilities.swift" "$P/Core/ConductorGesture.swift" \
  "$P/Core/AuthorizationModels.swift" "$P/Core/RemoteLayerHost.swift" "$P/App/WS2RemoteEffects.swift" "$P/App/ConductorSoundPlayer.swift" \
  "$P/Support/WS2PeerRepository.swift" "$P/Support/WS2PairSetupServer.swift" \
  "$P/Support/WS2CompanionCrypto.swift" "$P/Support/WS2CompanionTCPTransport.swift" \
  "$P/App/WS2RemoteHost.swift" "$ROOT/tests/RemoteHostLifecycleTests.swift" \
  -o "$OUT/remote-host-tests"
"$OUT/remote-host-tests"
