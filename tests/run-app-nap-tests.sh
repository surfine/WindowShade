#!/bin/bash
# PERF-10：进程级活动声明的分层、配对与计数（不需要图形会话）。
# 会真的调用 ProcessInfo 的 begin/endActivity（成对），并把日志写到
# ~/Library/Logs/WindowShade/app-nap-tests-<uuid>.log 供断言读回。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/app-nap-tests
swiftc -parse-as-library -O \
  prototype/Support/SecureLogFile.swift \
  prototype/Support/Diagnostics.swift \
  prototype/App/AppNapActivity.swift \
  tests/AppNapActivityTests.swift \
  -o .build/app-nap-tests/tests
.build/app-nap-tests/tests
