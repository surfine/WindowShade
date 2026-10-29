#!/usr/bin/env bash
# 「提示音」总开关的迁移账：三个旧键 → 一个新键（拍板 2026-10-29 第 1 条）。纯 Foundation。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build/alert-sound-tests"
swiftc -swift-version 6 -parse-as-library "$ROOT/prototype/Core/AlertSound.swift" "$ROOT/prototype/Core/ReleaseDefaults.swift" \
  "$ROOT/tests/AlertSoundPreferenceTests.swift" -o "$ROOT/.build/alert-sound-tests/alert-sound"
"$ROOT/.build/alert-sound-tests/alert-sound"
