#!/bin/bash
# FS-04：文件架卡的画面接线（整个 App 模块 + AppKit，不需要真屏幕；约 1 分钟，机器忙时更久）。
# 做法同 tests/run-appkit-tests.sh：把 prototype/ 下除 main.swift 以外的源文件和这份测试编成一个可执行文件。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/appkit-tests
NATIVE_DIR=".build/native"
mkdir -p "$NATIVE_DIR"
cc -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.0 -c prototype/Native/WS2Child.c -o "$NATIVE_DIR/WS2Child.o"
WORK="$(mktemp -d "$(pwd)/.build/appkit-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SOURCES=()
while IFS= read -r source; do
  mkdir -p "$WORK/$(dirname "$source")"
  cp "$source" "$WORK/$source"
  SOURCES+=("$WORK/$source")
done < <(rg --files prototype -g '*.swift' -g '!main.swift' -g '!*.app/**' | sort)
cp tests/FileShelfCardViewTests.swift "$WORK/FileShelfCardViewTests.swift"
GLASS_DEFINE=()
if [ -f "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  GLASS_DEFINE=(-DWINDOWSHADE_SDK_HAS_GLASS)
fi
swiftc -module-cache-path "$(pwd)/.build/module-cache" -whole-module-optimization -target "$(uname -m)-apple-macosx15.0" ${GLASS_DEFINE[@]+"${GLASS_DEFINE[@]}"} \
  -I prototype/Native "$NATIVE_DIR/WS2Child.o" \
  "${SOURCES[@]}" "$WORK/FileShelfCardViewTests.swift" \
  -framework Cocoa -framework Carbon -framework ApplicationServices -framework LocalAuthentication -framework LocalAuthenticationEmbeddedUI \
  -framework ScreenCaptureKit -framework QuartzCore -framework CoreText \
  -framework AVFoundation -framework Vision -framework ServiceManagement -framework Metal \
  -framework CoreAudio -framework MapKit -framework MetalKit -framework IOKit -framework CoreImage -framework VideoToolbox \
  -o ".build/appkit-tests/FileShelfCardViewTests"
".build/appkit-tests/FileShelfCardViewTests"
