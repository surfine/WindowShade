#!/bin/bash
# 正在播放大卡（NP-4）：几何、进度条按下 / 拖动 / 松手、时间写法、收回条件、输出设备、推送流判坏、开关默认值三态。
# 纯逻辑，无权限、无 UI、不起子进程。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/now-playing-card-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$root/prototype/Core/NowPlayingStreamParser.swift" "$root/prototype/Core/WireJSON.swift" "$root/prototype/Core/UsageReading.swift" "$root/prototype/Core/NotchActivities.swift" "$root/prototype/Core/ReleaseDefaults.swift" \
  "$root/prototype/Core/NowPlayingCardLogic.swift" "$root/tests/NowPlayingCardTests.swift" \
  -o "$root/.build/now-playing-card-tests/tests"
exec "$root/.build/now-playing-card-tests/tests"
