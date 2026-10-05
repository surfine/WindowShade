#!/bin/bash
# R02 真机：逐屏遮罩对账、重复请求复用面板、别的 App 前台时 Esc、退出无残留。
# 热插拔那一条要人手动插/拔一块屏；没等到会打印 not_run，不当成通过。
# 需要先 `cd prototype && WINDOWSHADE_CODESIGN_IDENTITY='…' ./build.sh --stage`。
# 不碰 Finder、浏览器、未保存的窗口，也不碰 /Applications 里每天在用的那份。
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
mkdir -p "$FIX/Contents/Resources"
codesign --force -s - "$FIX" >/dev/null 2>&1 || true
pkill -x GlanceFixture >/dev/null 2>&1 || true
APP=.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade
"$APP" --silent-cover-probe --fixture "$FIX/Contents/MacOS/GlanceFixture"
