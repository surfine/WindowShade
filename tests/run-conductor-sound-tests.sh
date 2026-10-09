#!/usr/bin/env bash
# 指挥提示音（R11）：事件到音色的映射、合成的时长与走向、开关关着不播放。不开音频设备。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/conductor-sound"
mkdir -p "$BUILD/module-cache"
P="$ROOT/prototype"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -D WS2_REMOTE_HOST_TESTING -module-cache-path "$BUILD/module-cache" \
  "$P/Core/Contracts.swift" "$P/Core/ConductorSession.swift" "$P/Core/ConductorCapabilities.swift" \
  "$P/Core/ConductorGesture.swift" "$P/App/ConductorSoundPlayer.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" "$ROOT/tests/ConductorSoundTests.swift" -o "$BUILD/conductor-sound-tests"
"$BUILD/conductor-sound-tests"
