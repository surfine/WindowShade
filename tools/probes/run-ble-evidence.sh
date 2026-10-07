#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=.build/ws2-reuse
mkdir -p "$OUT/module-cache"
cat > "$OUT/ble-Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.windowshade.ble-evidence-probe</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>仅在本次指定设备实验中，验证蓝牙连接和受保护服务；不读取通知内容。</string>
</dict></plist>
PLIST
swiftc -module-cache-path "$OUT/module-cache" -parse-as-library tools/probes/BLEReadProbe.swift \
 -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$OUT/ble-Info.plist" -o "$OUT/ble-probe"
if [[ "${1:-}" == --check ]]; then echo 'BLE probe compiled, radio not started'; exit 0; fi
exec "$OUT/ble-probe" "$@"
