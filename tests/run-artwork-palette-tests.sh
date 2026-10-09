#!/bin/bash
# 正在播放封面取色（NP-1）：纯逻辑 + 一次内存里的 PNG 解码，无权限、无 UI、不起子进程。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/artwork-palette-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  "$root/prototype/Core/ArtworkPalette.swift" "$root/prototype/Core/NowPlayingStreamParser.swift" "$root/prototype/Core/NowPlayingCardLogic.swift" \
  "$root/prototype/App/NowPlayingArtwork.swift" "$root/prototype/App/NowPlayingStream.swift" \
  "$root/prototype/App/NotchActivityPollPolicy.swift" "$root/prototype/Core/NotchActivities.swift" \
  "$root/tests/ArtworkPaletteTests.swift" -o "$root/.build/artwork-palette-tests/tests"
exec "$root/.build/artwork-palette-tests/tests"
