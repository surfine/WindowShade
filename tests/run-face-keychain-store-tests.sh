#!/bin/bash
# 刷脸模板钥匙串的存不了判断（纯逻辑，不碰真实钥匙串）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/face-keychain-store-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/SessionLockState.swift prototype/Core/FaceScanGuard.swift \
  prototype/Core/FaceTemplateSet.swift prototype/App/FaceTemplateKeychainStore.swift \
  tests/FaceTemplateKeychainStoreTests.swift -o .build/face-keychain-store-tests/store
.build/face-keychain-store-tests/store
