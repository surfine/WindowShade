#!/bin/bash
# PERF-04：旧系统呈现用的最新一帧邮箱（有界占用、新帧覆盖、stop/start 作废旧会话）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/capture-mailbox-tests
swiftc -module-cache-path "$(pwd)/.build/module-cache" \
  prototype/Capture/LatestFrameMailbox.swift \
  tests/CaptureMailboxTests.swift \
  -o .build/capture-mailbox-tests/capture-mailbox
.build/capture-mailbox-tests/capture-mailbox
