#!/bin/bash
# Build a local WindowShade.app bundle.
#
# By default this uses ad-hoc signing so the prototype can run locally.
# For a stable local TCC identity, pass your own signing certificate:
#   CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh

set -euo pipefail
cd "$(dirname "$0")"

APP="WindowShade.app"
BIN="$APP/Contents/MacOS/WindowShade"
RES="$APP/Contents/Resources"
TMP_BIN="windowshade"
MODULE_CACHE="$(cd .. && pwd -P)/.build/module-cache-public"
IDENTITY="${CODESIGN_IDENTITY:--}"

mkdir -p "$APP/Contents/MacOS" "$RES" "$MODULE_CACHE"
cp Info.plist "$APP/Contents/Info.plist"
if [ -f "../assets/app-icon/WindowShade.icns" ]; then
  cp "../assets/app-icon/WindowShade.icns" "$RES/WindowShade.icns"
fi

echo "==> Stopping running WindowShade, if any"
pkill -x WindowShade 2>/dev/null || true

echo "==> Compiling"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -O -o "$TMP_BIN" \
  main.swift \
  WindowShade.swift \
  ScreenCaptureBridge.swift \
  PinnedPreviewPanel.swift \
  PinnedPreview.swift \
  -framework Cocoa -framework Carbon -framework ApplicationServices \
  -framework ScreenCaptureKit -framework QuartzCore -framework CoreText \
  -framework AVFoundation \
  -framework ServiceManagement

cp "$TMP_BIN" "$BIN"

echo "==> Signing with ${IDENTITY}"
codesign --force -s "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
touch "$APP"

echo "==> Built $(pwd)/$APP"
