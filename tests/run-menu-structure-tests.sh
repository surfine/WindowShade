#!/bin/bash
# D20B：菜单栏菜单顶层固定 9 项、动态行只在进行中出现、旧 action 都还能从某处触发。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/menu-structure-tests
swiftc -O -swift-version 6 -parse-as-library prototype/App/StandardMenu.swift tests/MenuStructureTests.swift \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  -o .build/menu-structure-tests/run
.build/menu-structure-tests/run
