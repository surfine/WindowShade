#!/bin/bash
# 功能目录、默认矩阵与首次播种。纯 Core，不启动 App。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/feature-catalog-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Core/WSL10n.swift \
  prototype/Core/PrivacyPaneName.swift \
  prototype/Core/FeatureCatalog.swift prototype/Core/PlatformSupport.swift \
  prototype/Core/InstallFeatureDefaults.swift \
  tests/FeatureCatalogTests.swift \
  -o .build/feature-catalog-tests/tests
.build/feature-catalog-tests/tests
