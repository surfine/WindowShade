#!/bin/bash
# 应用内更新：版本比较、能不能一键更新的判断、每一版启动的收尾、看护的决策表、日志读写、
# 找 Sparkle 解开的 App、备份与换回（真签名的小 App 也在临时目录里造）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/update-tests .build/module-cache
tmp="$(mktemp -d "$PWD/.build/update-tests/tmp.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library \
    -module-cache-path .build/module-cache \
    -o .build/update-tests/UpdateTests \
    prototype/Core/UpdateVersion.swift prototype/Core/UpdateModels.swift prototype/Core/UpdateDecisions.swift \
    prototype/App/UpdaterSystem.swift tests/UpdateTests.swift \
    -framework Security -framework ServiceManagement
UPDATE_TEST_TMP="$tmp" .build/update-tests/UpdateTests
