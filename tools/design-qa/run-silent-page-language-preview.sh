#!/bin/bash
# 第28批：静音页中英夹具（轻量档）。先编译目录表（en.lproj），再编整套生产源 + 夹具入口，
# 隐藏窗口离屏渲染；夹具只直接设 WSL10n.language，不写偏好、不碰相机。
# 用法：bash tools/design-qa/run-silent-page-language-preview.sh [ABS_OUTPUT]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/.build/design-qa/silent-page-language}"
ENTRY="$ROOT/tools/design-qa/SilentPageLanguagePreview.swift"
mkdir -p "$OUT"
xcrun xcstringstool compile "$ROOT/prototype/Resources/Localizable.xcstrings" -o "$OUT/strings"
WS2_LOCALIZATION_DIR="$OUT/strings" bash "$ROOT/tools/design-qa/render-native-surfaces.sh" "$OUT" "$ENTRY" --swift6
