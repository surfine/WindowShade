#!/bin/bash
# 设置搜索（1.0.18 新表面稿第 2 节）：同义词表与 copy-guide「不要用」列一致、拼音、同义词、排序、命中区间、
# 空结果、藏着的页不出现（纯逻辑，不编整个 App）；再查一遍行构造器的 settings.*.name 键都进了索引。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/settings-search-tests
swiftc -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/LaunchpadModel.swift \
  prototype/Core/SettingsSearch.swift prototype/Core/SettingsSearchSynonyms.swift \
  tests/SettingsSearchTests.swift -o .build/settings-search-tests/run
.build/settings-search-tests/run
