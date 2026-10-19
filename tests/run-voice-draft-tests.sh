#!/usr/bin/env bash
# 语音草稿的纯状态：松手才出草稿、60 秒上限、空结果/取消/失败。不碰麦克风。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/voice-draft"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/VoiceDraft.swift" \
  "$ROOT/tests/VoiceDraftTests.swift" \
  -o "$BUILD/voice-draft-tests"
"$BUILD/voice-draft-tests" "$@"
