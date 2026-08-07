#!/bin/bash
# 编译 WindowShade 主实现，替换现有 app bundle 里的 Mach-O，并用稳定开发者证书签名。
set -euo pipefail
cd "$(dirname "$0")"

APP="WindowShade.app"
BIN="$APP/Contents/MacOS/WindowShade"
TMP_BIN="windowshade"
IDENTITY="Apple Development: openkams@gmail.com (G3TN2MBQ2Q)"
MODULE_CACHE="$(cd .. && pwd)/.build/module-cache"

if ! security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "ERROR: 未找到 ${IDENTITY}；拒绝 ad-hoc 签名，避免重置 TCC 授权。" >&2
  exit 1
fi

if [ ! -d "$APP/Contents/MacOS" ]; then
  echo "ERROR: 未找到现有 ${APP} bundle；拒绝重建 bundle，避免丢失手工资源或改变 TCC 身份。" >&2
  exit 1
fi

echo "==> 停止正在运行的 WindowShade（避免运行中替换 Mach-O 触发 TCC 混乱）"
pkill -x WindowShade 2>/dev/null || true

echo "==> 编译"
mkdir -p "$MODULE_CACHE"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -O -o "$TMP_BIN" \
  main.swift \
  WindowShade.swift \
  ScreenCaptureBridge.swift \
  PinnedPreviewPanel.swift \
  PinnedPreview.swift \
  Private/SkyLightBridge.swift \
  Compatibility/WindowPolicy.swift \
  Compatibility/Policies.swift \
  Core/WindowState.swift \
  Capture/WindowSnapshotCache.swift \
  Capture/PreviewRenderer.swift \
  Overlay/ShadeStripPool.swift \
  Overlay/ShadeStrip.swift \
  Window/WindowRegistry.swift \
  Window/AXWindow.swift \
  Recovery/Journal.swift \
  Recovery/Rescue.swift \
  App/MenuBarController.swift \
  App/Reconcile.swift \
  App/EventTap.swift \
  App/Preferences.swift \
  App/OverlayPresentation.swift \
  App/HoverPreview.swift \
  App/OverlayFactory.swift \
  App/ArrangeController.swift \
  App/FocusSession.swift \
  App/FoldTransaction.swift \
  -framework Cocoa -framework Carbon -framework ApplicationServices \
  -framework ScreenCaptureKit -framework QuartzCore -framework CoreText \
  -framework AVFoundation \
  -framework ServiceManagement

echo "==> 替换 Mach-O（保留 bundle、Info.plist、Resources）"
cp "$TMP_BIN" "$BIN"

echo "==> 用 Apple Development 证书签名（TCC 授权可跨重编保留）"
codesign --force -s "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
touch "$APP"

echo "==> 完成：$(pwd)/$APP"
codesign -dv "$APP" 2>&1 | sed 's/^/    /'
