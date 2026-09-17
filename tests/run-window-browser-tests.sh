#!/bin/bash
# 窗口浏览纯逻辑测试：只编译明确列出的生产源文件，测试不触碰系统权限、
# 不操作用户窗口、不注入事件、不访问网络。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/window-browser-tests

swiftc -target "$(uname -m)-apple-macosx14.0" \
  prototype/WindowBrowser/WindowBrowserModels.swift \
  prototype/WindowBrowser/WindowBrowserTypography.swift \
  prototype/WindowBrowser/WindowBrowserGeometry.swift \
  prototype/WindowBrowser/WindowBrowserActions.swift \
  prototype/WindowBrowser/WindowBrowserDiscoveryFilter.swift \
  prototype/WindowBrowser/WindowBrowserThumbnailPolicy.swift \
  prototype/WindowBrowser/WindowMirrorSlot.swift \
  prototype/WindowBrowser/WindowThumbnailService.swift \
  prototype/WindowBrowser/WindowCatalog.swift \
  prototype/WindowBrowser/WindowBrowserViews.swift \
  prototype/WindowBrowser/WindowBrowserPanel.swift \
  prototype/WindowBrowser/WindowBrowserSettings.swift \
  prototype/Capture/WindowSnapshotCache.swift \
  prototype/Overlay/PaperSurfaceStyle.swift \
  tests/WindowBrowserTests.swift \
  -framework Cocoa -framework AVFoundation \
  -o .build/window-browser-tests/core
.build/window-browser-tests/core
