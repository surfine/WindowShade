#!/bin/bash
# 运行记录的安全写入（Support/SecureLogFile.swift）：0700 目录、0600 文件、拒绝链接、轮转、空 ACL。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/secure-log-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  tests/support/WS2TestSupport.swift prototype/Core/Contracts.swift \
  prototype/Support/SecureLogFile.swift tests/SecureLogFileTests.swift -o .build/secure-log-tests/tests
.build/secure-log-tests/tests
