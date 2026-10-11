#!/bin/bash
# ID-07 真机探针：镜头 yaw 与 AirPods yaw 的左右符号和起转时差。--check 只编译、不开相机。
set -euo pipefail
cd "$(dirname "$0")/../../.."
BUILD=.build/head-motion-crosscheck-probe
mkdir -p "$BUILD/module-cache"
cat > "$BUILD/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.windowshade.head-motion-crosscheck-probe</string>
<key>NSCameraUsageDescription</key><string>只在这次测量里看你的转头方向；不保存图像。</string>
<key>NSMotionUsageDescription</key><string>只在这次测量里读 AirPods 的转头方向；不保存。</string>
</dict></plist>
PLIST
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path "$BUILD/module-cache" \
  prototype/Core/Contracts.swift prototype/Core/WS2HeadGesture.swift prototype/Core/WS2HeadMotionFeed.swift \
  prototype/Core/HeadMotionCrossCheck.swift tools/probes/head-motion-crosscheck/HeadMotionCrossCheckProbe.swift \
  -framework AVFoundation -framework Vision -framework CoreMotion -framework CoreMedia \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$BUILD/Info.plist" \
  -o "$BUILD/probe"
if [[ "${1:-}" == --check ]]; then
  [[ $# -eq 1 ]] || { echo '--check 不能与测量参数混用'; exit 64; }
  echo 'HeadMotionCrossCheckProbe compiled; camera and headphones not opened'
  exit 0
fi
"$BUILD/probe" "$@"
