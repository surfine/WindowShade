#!/bin/bash
# 看一眼真机探针：需要先 `cd prototype && ./build.sh --stage`（签名隔离构建，已授权辅助功能与屏幕录制）。
# 会在屏幕上短暂出现测试窗口；不操作用户自己的窗口。
set -euo pipefail
cd "$(dirname "$0")/.."
FIX=.build/glance-tests/GlanceFixture.app
mkdir -p "$FIX/Contents/MacOS"
swiftc tests/fixtures/GlanceFixture.swift -o "$FIX/Contents/MacOS/GlanceFixture"
cat > "$FIX/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.windowshade.glance-fixture</string>
<key>CFBundleName</key><string>GlanceFixture</string>
<key>CFBundleExecutable</key><string>GlanceFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force -s - "$FIX" >/dev/null 2>&1 || true
APP=.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade
"$APP" --glance-probe --fixture "$FIX/Contents/MacOS/GlanceFixture" "$@"
