#!/bin/bash
# 刘海实时活动 store 与下载进度卡：纯 Foundation 逻辑测试，无权限、无 UI、无网络。
# 含 PERF-08 的轮询档位策略（NotchActivityPollPolicy，不碰 AppKit）。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/notch-activity-tests"
swiftc "$root/prototype/Core/WSL10n.swift" "$root/prototype/Core/WireJSON.swift" "$root/prototype/Core/UsageReading.swift" "$root/prototype/Core/NotchActivities.swift" "$root/prototype/Core/ReleaseDefaults.swift" "$root/prototype/App/NotchActivityPollPolicy.swift" \
  "$root/tests/NotchActivityTests.swift" \
  -o "$root/.build/notch-activity-tests/tests"
"$root/.build/notch-activity-tests/tests"
# 计划 2-1：正在播放推送流的解析器与退路决策（不启动子进程）。
swiftc -swift-version 6 "$root/prototype/Core/NowPlayingStreamParser.swift" "$root/prototype/App/NotchActivityPollPolicy.swift" \
  "$root/tests/NowPlayingStreamTests.swift" -o "$root/.build/notch-activity-tests/now-playing-tests"
"$root/.build/notch-activity-tests/now-playing-tests"
swiftc "$root/prototype/Core/WSL10n.swift" "$root/prototype/Core/WireJSON.swift" "$root/prototype/Core/UsageReading.swift" "$root/prototype/Core/NotchActivities.swift" "$root/prototype/Core/ReleaseDefaults.swift" "$root/prototype/Core/DownloadActivity.swift" "$root/prototype/Core/NotchSentence.swift" \
  "$root/tests/DownloadActivityTests.swift" -o "$root/.build/notch-activity-tests/download-tests"
exec "$root/.build/notch-activity-tests/download-tests"
