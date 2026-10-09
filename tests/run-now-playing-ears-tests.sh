#!/bin/bash
# 正在播放紧凑两耳（NP-2）：纯逻辑，无权限、无 UI、不起子进程。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/now-playing-ears-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  "$root/prototype/Core/ArtworkPalette.swift" "$root/prototype/Core/NowPlayingEars.swift" \
  "$root/tests/NowPlayingEarsTests.swift" -o "$root/.build/now-playing-ears-tests/tests"
exec "$root/.build/now-playing-ears-tests/tests"
