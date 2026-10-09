#!/usr/bin/env bash
# 遥控器第 0、1 层的宿主与效果执行（M09）：层转移表、10 秒收回、本地的人优先、断线不放回、挂起后恢复不重播。
# 纯状态机 + 替身端口：不碰刘海、启动台、CoreAudio，不开真实定时器。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/remote-layer"
mkdir -p "$OUT/module-cache"
P="$ROOT/prototype"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -D WS2_REMOTE_HOST_TESTING -module-cache-path "$OUT/module-cache" \
  "$P/Core/Contracts.swift" "$P/Core/RemoteMode.swift" \
  "$P/Core/ConductorSession.swift" "$P/Core/ConductorCapabilities.swift" "$P/Core/ConductorGesture.swift" \
  "$P/Core/RemoteLayerHost.swift" "$P/App/WS2RemoteEffects.swift" "$P/App/ConductorSoundPlayer.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/RemoteLayerHostTests.swift" \
  -o "$OUT/remote-layer-tests"
"$OUT/remote-layer-tests"
