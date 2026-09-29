#!/bin/bash
# “少做”的默认值：⌃⌘ 快捷键新装的不占、升级的照旧；“让开这个 App”的守卫和默认值（纯逻辑，不碰用户的设置和窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/quiet-defaults-tests
swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  prototype/App/GlobalShortcuts.swift prototype/Core/DockClickGuard.swift prototype/Core/SwitcherOrigin.swift \
  tests/QuietDefaultsTests.swift -o .build/quiet-defaults-tests/quiet
.build/quiet-defaults-tests/quiet
