#!/bin/bash
# R05：崩溃后放回提醒（n>0 才说）、上次检查更新的写法、缩略图模式的标题变化刘海不跟。纯 Foundation。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/rescue-announce-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/NotchSentence.swift prototype/Core/RescueAnnounce.swift \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift \
  prototype/Core/NotchChangeFilter.swift prototype/App/UpdaterCopy.swift tests/RescueAnnounceTests.swift \
  -o .build/rescue-announce-tests/tests
.build/rescue-announce-tests/tests
