#!/bin/bash
# 平台能力（Intel 版不带的功能）：谓词、功能目录过滤、探针开关。纯 Core，不启动 App。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/platform-support-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Core/WSL10n.swift \
  prototype/Core/PrivacyPaneName.swift \
  prototype/Core/PlatformSupport.swift \
  prototype/Core/FeatureCatalog.swift \
  tests/PlatformSupportTests.swift \
  -o .build/platform-support-tests/tests
.build/platform-support-tests/tests
