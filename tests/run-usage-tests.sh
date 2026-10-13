#!/bin/bash
# 用量（实验）：额度事件解析、10% 以内只提醒一次、没有数据回退、不压过“等你”。纯 Foundation，无权限、无 UI、无网络。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/usage-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift \
  "$root/prototype/Core/Contracts.swift" "$root/prototype/Core/WS2StrictJSON.swift" "$root/prototype/Core/CodexWire.swift" \
  "$root/prototype/Core/NotchActivities.swift" "$root/prototype/Core/ReleaseDefaults.swift" "$root/prototype/Core/WireJSON.swift" "$root/prototype/Core/UsageReading.swift" \
  "$root/tests/UsageReadingTests.swift" -o "$root/.build/usage-tests/tests"
exec "$root/.build/usage-tests/tests"
