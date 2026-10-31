#!/bin/bash
# Wraps the probe in a tiny ad-hoc-signed .app so macOS asks Bluetooth permission for IT (not for the terminal/host app).
# Usage: make-app.sh OUT_DIR   -> OUT_DIR/ContinuityProbe.app ; run: open -W -o out.txt --stderr err.txt OUT_DIR/ContinuityProbe.app --args --seconds 60
set -euo pipefail
cd "$(dirname "$0")"; out="${1:?out dir}"; app="$out/ContinuityProbe.app"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
./build.sh "$app/Contents/MacOS/ContinuityProbe"
cat > "$app/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.windowshade.continuity-probe</string>
<key>CFBundleName</key><string>ContinuityProbe</string>
<key>CFBundleExecutable</key><string>ContinuityProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>Experiment: read nearby Apple Continuity advertisements to test a recently-unlocked signal.</string>
</dict></plist>
P
codesign --force --sign - "$app"
