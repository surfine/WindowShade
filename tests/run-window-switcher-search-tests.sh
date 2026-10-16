#!/bin/bash
# 切换器打字搜索（O1）：纯逻辑，无权限、无 UI。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/window-switcher-search-tests"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  "$root/prototype/Core/WindowSwitcherSearch.swift" "$root/tests/WindowSwitcherSearchTests.swift" \
  -o "$root/.build/window-switcher-search-tests/tests"
exec "$root/.build/window-switcher-search-tests/tests"
