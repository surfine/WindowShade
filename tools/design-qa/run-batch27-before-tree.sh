#!/bin/bash
# 第27批 before 树基线重建：检出第27批入库提交（2003e53）的父提交——它就是改动前快照
#（.statem/history-design-twentyseventh-round/source 的 15 个文件与其逐字节一致，2026-10-12 核对）——
# 到 BUILD_DIR（默认 /tmp/batch27-before），配上当前夹具，编出 render 并跑出 zh 基线帧。
#
# 与 tools/design-qa/run-settings-shade-language-preview.sh 同构，差别只在 SOURCE 指向父提交检出；
# 夹具用仓库里当前这一份（含诊断探针），所以 **基线和新帧必须用同一版夹具重跑**，否则几何对比无意义。
# 基线只需要 zh 帧：不编也不发 WS2_LOCALIZATION_DIR（en 帧会回退中文，不用于对比）。
#
# 用法：bash tools/design-qa/run-batch27-before-tree.sh [BUILD_DIR] [OUT_DIR]
#   BUILD_DIR 默认 /tmp/batch27-before；OUT_DIR 默认 BUILD_DIR/out。
#   BEFORE_COMMIT 默认 2003e53^（第23–27批入库提交的父提交）。
# 耗时约 15–25 分钟（未优化整模块编译，和 after 一致）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SNAP="${BEFORE_COMMIT:-2003e53^}"
BUILD="${1:-/tmp/batch27-before}"
OUT="${2:-$BUILD/out}"
ENTRY="$ROOT/tools/design-qa/SettingsShadeLanguagePreview.swift"

rm -rf "$BUILD"
mkdir -p "$BUILD"
# 完整源码树从 git 检出（历史重写后 2003e53^ 仍是有效对象；旧 SHA 对照表在
# .statem/history-design-twentyseventh-round/qa/commit-map-final-2026-10-12.txt）。
git -C "$ROOT" archive "$SNAP" prototype | tar -x -C "$BUILD"
# Native 的 C 端口连同 modulemap 一起检出，后面就地编译；modulemap 和 header 要放进 -I 指向的目录。
mkdir -p "$BUILD/native"
cp "$BUILD/prototype/Native/module.modulemap" "$BUILD/prototype/Native/WS2Child.h" "$BUILD/native/"
cc -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
   -c "$BUILD/prototype/Native/WS2Child.c" -o "$BUILD/native/WS2Child.o"

# 与 render-native-surfaces.sh 相同的生产源快照方式：去掉产品 main，避免顶格代码。
WORK="$BUILD/work"
rm -rf "$WORK"
mkdir -p "$WORK"
SOURCES=()
while IFS= read -r source; do
  mkdir -p "$WORK/$(dirname "$source")"
  cp "$BUILD/$source" "$WORK/$source"
  SOURCES+=("$WORK/$source")
done < <(cd "$BUILD" && rg --files prototype -g '*.swift' -g '!main.swift' -g '!*.app/**' | sort)
cp "$ENTRY" "$WORK/SettingsShadeLanguagePreview.swift"

GLASS_DEFINE=()
if [ -f "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  GLASS_DEFINE=(-DWINDOWSHADE_SDK_HAS_GLASS)
fi
mkdir -p "$BUILD/mc"
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$BUILD/mc" -whole-module-optimization -target "$(uname -m)-apple-macosx14.0" \
  ${GLASS_DEFINE[@]+"${GLASS_DEFINE[@]}"} \
  -I "$BUILD/native" "$BUILD/native/WS2Child.o" \
  "${SOURCES[@]}" "$WORK/SettingsShadeLanguagePreview.swift" \
  -framework Cocoa -framework Carbon -framework ApplicationServices -framework LocalAuthentication -framework LocalAuthenticationEmbeddedUI \
  -framework ScreenCaptureKit -framework QuartzCore -framework CoreText \
  -framework AVFoundation -framework Vision -framework ServiceManagement -framework Metal \
  -framework CoreAudio -framework MapKit -framework MetalKit -framework IOKit -framework CoreImage -framework VideoToolbox \
  -o "$BUILD/render"

mkdir -p "$OUT"
"$BUILD/render" "$OUT"
