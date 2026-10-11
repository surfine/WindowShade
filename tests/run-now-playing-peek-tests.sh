#!/bin/bash
# 正在播放换歌一瞥（NP-3）：停多久、开口 / 原地换字 / 不一瞥的条件。纯逻辑，无权限、无 UI、不起子进程。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/now-playing-peek-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$root/prototype/Core/NowPlayingStreamParser.swift" "$root/prototype/Core/WireJSON.swift" "$root/prototype/Core/UsageReading.swift" "$root/prototype/Core/NotchActivities.swift" "$root/prototype/Core/ReleaseDefaults.swift" \
  "$root/prototype/Core/NowPlayingCardLogic.swift" "$root/prototype/Core/NotchAlerts.swift" \
  "$root/tests/NowPlayingPeekTests.swift" \
  -o "$root/.build/now-playing-peek-tests/tests"
exec "$root/.build/now-playing-peek-tests/tests"
