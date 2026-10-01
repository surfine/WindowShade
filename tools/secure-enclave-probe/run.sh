#!/bin/bash
# Secure Enclave 能力探针（认证里程碑 A0）。用和 WindowShade 相同的开发证书签名、同样不带 entitlements。
#   bash tools/secure-enclave-probe/run.sh --check          不需要手指
#   bash tools/secure-enclave-probe/run.sh --sign=policy    需要手指（也可 acl / direct）
#   bash tools/secure-enclave-probe/run.sh --state | --cleanup
set -euo pipefail
cd "$(dirname "$0")/../.."
APP=.build/secure-enclave-probe/SEProbe.app
mkdir -p "$APP/Contents/MacOS"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx14.0" \
  tools/secure-enclave-probe/main.swift -framework Cocoa -framework CryptoKit -framework Security \
  -framework LocalAuthentication -framework LocalAuthenticationEmbeddedUI \
  -o "$APP/Contents/MacOS/SEProbe"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SEProbe</string>
<key>CFBundleIdentifier</key><string>me.aaronlau.WindowShade.SEProbe</string>
<key>CFBundleName</key><string>Secure Enclave 探针</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
SIGN_IDENTITY="${WINDOWSHADE_CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY=$(codesign -dv --verbose=2 /Applications/WindowShade.app 2>&1 | sed -n 's/^Authority=\(Apple Development:.*\)/\1/p' | head -n 1)
fi
if [ -z "$SIGN_IDENTITY" ]; then
  echo '请用 WINDOWSHADE_CODESIGN_IDENTITY 指定现有开发证书。' >&2; exit 1
fi
# 和主 App 一样：不带 entitlements、不开 hardened runtime。
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"
exec "$APP/Contents/MacOS/SEProbe" "${1:---check}"
