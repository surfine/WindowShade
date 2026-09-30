#!/bin/bash
# 刘海实时活动 store：纯 Foundation 逻辑测试，无权限、无 UI、无网络。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/notch-activity-tests"
swiftc "$root/prototype/Core/NotchActivities.swift" "$root/tests/NotchActivityTests.swift" \
  -o "$root/.build/notch-activity-tests/tests"
exec "$root/.build/notch-activity-tests/tests"
