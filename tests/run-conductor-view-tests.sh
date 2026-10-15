#!/usr/bin/env bash
# 指挥回合的刘海画面（R10）：形状尺寸、拍点亮灭、波形、草稿没把握的词、判定后的两行字。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/conductor-view"
mkdir -p "$BUILD"
"${SWIFTC:-swiftc}" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$ROOT/prototype/Core/WSL10n.swift" "$ROOT/prototype/Core/PrivacyPaneName.swift" "$ROOT/prototype/Core/Contracts.swift" \
  "$ROOT/prototype/Core/ConductorSession.swift" \
  "$ROOT/prototype/Core/ConductorCapabilities.swift" \
  "$ROOT/prototype/Core/ConductorGesture.swift" \
  "$ROOT/tests/support/WS2TestSupport.swift" \
  "$ROOT/tests/ConductorViewModelTests.swift" -o "$BUILD/conductor-view-tests"
"$BUILD/conductor-view-tests"
