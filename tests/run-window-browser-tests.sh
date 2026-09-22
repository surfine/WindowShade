#!/bin/bash
# 窗口浏览纯逻辑测试：只编译明确列出的生产源文件，测试不触碰系统权限、
# 不操作用户窗口、不注入事件、不访问网络。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/window-browser-tests

GLASS_DEFINE=""
if [ -f "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  GLASS_DEFINE="-DWINDOWSHADE_SDK_HAS_GLASS"
fi

swiftc -target "$(uname -m)-apple-macosx14.0" $GLASS_DEFINE \
  prototype/App/StandardMenu.swift \
  prototype/App/GlobalShortcuts.swift \
  prototype/WindowBrowser/WindowBrowserModels.swift \
  prototype/WindowBrowser/WindowBrowserTypography.swift \
  prototype/WindowBrowser/WindowBrowserGeometry.swift \
  prototype/WindowBrowser/WindowBrowserActionPresentation.swift \
  prototype/WindowBrowser/WindowBrowserMaterial.swift \
  prototype/WindowBrowser/WindowBrowserMetadataScheduler.swift \
  prototype/WindowBrowser/WindowBrowserTargetBatch.swift \
  prototype/WindowBrowser/WindowBrowserDockDetection.swift \
  prototype/WindowBrowser/WindowPlacement.swift \
  prototype/WindowBrowser/WindowBrowserActions.swift \
  prototype/WindowBrowser/WindowBrowserDiscoveryFilter.swift \
  prototype/WindowBrowser/WindowBrowserThumbnailPolicy.swift \
  prototype/WindowBrowser/WindowMirrorSlot.swift \
  prototype/WindowBrowser/WindowThumbnailService.swift \
  prototype/WindowBrowser/WindowCatalog.swift \
  prototype/WindowBrowser/WindowBrowserViews.swift \
  prototype/WindowBrowser/WindowBrowserActionBar.swift \
  prototype/WindowBrowser/WindowBrowserCardView.swift \
  prototype/WindowBrowser/WindowBrowserListRowView.swift \
  prototype/WindowBrowser/WindowBrowserSelectionDetailView.swift \
  prototype/WindowBrowser/WindowBrowserQuickLookView.swift \
  prototype/WindowBrowser/WindowBrowserContentView.swift \
  prototype/WindowBrowser/WindowBrowserPanel.swift \
  prototype/WindowBrowser/WindowBrowserSettings.swift \
  prototype/Capture/WindowSnapshotCache.swift \
  prototype/Overlay/SystemAppearance.swift prototype/Overlay/PaperSurfaceStyle.swift \
  tests/WindowBrowserTests.swift \
  -framework Cocoa -framework AVFoundation \
  -o .build/window-browser-tests/core
.build/window-browser-tests/core

swiftc -target "$(uname -m)-apple-macosx14.0" \
  prototype/WindowBrowser/WindowBrowserPreviewStartup.swift \
  tests/WindowBrowserPreviewStartupTests.swift \
  -o .build/window-browser-tests/preview-startup
.build/window-browser-tests/preview-startup

swiftc -target "$(uname -m)-apple-macosx14.0" \
  prototype/WindowBrowser/WindowBrowserMetadataQueue.swift \
  tests/MetadataQueueTests.swift \
  -o .build/window-browser-tests/metadata-queue
.build/window-browser-tests/metadata-queue
