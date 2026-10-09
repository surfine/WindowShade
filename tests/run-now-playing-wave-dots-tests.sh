#!/bin/bash
# 大卡里的右耳波形（NP36）：纯逻辑。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/now-playing-wave-dots-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  "$root/prototype/Core/ArtworkPalette.swift" "$root/prototype/Core/NowPlayingEars.swift" \
  "$root/prototype/Core/AudioLevelBands.swift" "$root/prototype/Core/NowPlayingWaveDots.swift" \
  "$root/tests/NowPlayingWaveDotsTests.swift" -o "$root/.build/now-playing-wave-dots-tests/tests"
exec "$root/.build/now-playing-wave-dots-tests/tests"
