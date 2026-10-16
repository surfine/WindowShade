#!/bin/bash
# secure-input-notice：纯逻辑判定（不需要图形会话，不碰系统）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/secure-input-notice-tests
swiftc -parse-as-library -target arm64-apple-macos15.0 prototype/Core/SecureInputNoticeGate.swift tests/SecureInputNoticeTests.swift -o .build/secure-input-notice-tests/secure-input-notice
.build/secure-input-notice-tests/secure-input-notice
