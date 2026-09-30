#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
APP=.build/touch-id-island/TouchIDIsland.app
mkdir -p "$APP/Contents/MacOS"
swiftc -swift-version 6 -O -target "$(uname -m)-apple-macosx14.0" \
  tools/touch-id-island/main.swift -framework Cocoa -framework QuartzCore \
  -framework LocalAuthentication -framework LocalAuthenticationEmbeddedUI \
  -o "$APP/Contents/MacOS/TouchIDIsland"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TouchIDIsland</string>
<key>CFBundleIdentifier</key><string>me.aaronlau.WindowShade.TouchIDIsland</string>
<key>CFBundleName</key><string>Touch ID 动画小样</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
SIGN_IDENTITY="${WINDOWSHADE_CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY=$(codesign -dv --verbose=2 prototype/WindowShade.app 2>&1 | sed -n 's/^Authority=\(Apple Development:.*\)/\1/p' | head -n 1)
fi
if [ -z "$SIGN_IDENTITY" ]; then
  echo '请用 WINDOWSHADE_CODESIGN_IDENTITY 指定现有开发证书。' >&2; exit 1
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"
exec "$APP/Contents/MacOS/TouchIDIsland" "${1:---check}"
