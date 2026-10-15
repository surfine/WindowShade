#!/bin/bash
# 编程会话成为持续活动（M08）：权重、等你只开口一次、做完留 4 秒后移除、菜单行、60 秒冷却、“过去”认终端窗口。
# 纯 Foundation 逻辑，无权限、无 UI、无网络。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/session-activity-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  "$root/prototype/Core/WireJSON.swift" "$root/prototype/Core/UsageReading.swift" "$root/prototype/Core/NotchActivities.swift" "$root/prototype/Core/ReleaseDefaults.swift" "$root/tests/SessionActivityTests.swift" \
  -o "$root/.build/session-activity-tests/tests"
exec "$root/.build/session-activity-tests/tests"
