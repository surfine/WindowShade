#!/bin/bash
# M03：私人 App 名单（只依赖 Foundation）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/private-app-list-tests
swiftc -parse-as-library -O -swift-version 6 \
  prototype/Core/PrivateAppList.swift \
  tests/PrivateAppListTests.swift \
  -o .build/private-app-list-tests/tests
.build/private-app-list-tests/tests
