#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
BUILD=.build/mouth-recording-probe
mkdir -p "$BUILD/module-cache"
cat > "$BUILD/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.windowshade.mouth-recording-probe</string>
<key>NSCameraUsageDescription</key><string>仅在显式个人录入时，采集约两秒嘴部几何；不保存图像或录音。</string>
</dict></plist>
PLIST
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  -module-cache-path "$BUILD/module-cache" \
  prototype/App/FaceObservationSource.swift prototype/App/FaceVisionFallback.swift \
  prototype/Core/WS2SilentCatalog.swift prototype/Core/WS2SilentPhrases.swift prototype/Core/WS2MouthTemplates.swift \
  tools/probes/MouthRecordingProbe.swift -framework AVFoundation -framework Vision -framework CoreVideo \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$BUILD/Info.plist" \
  -o "$BUILD/record"
if [[ "${1:-}" == --check ]]; then
  [[ $# -eq 1 ]] || { echo '--check 不能与采集参数混用'; exit 64; }
  echo 'MouthRecordingProbe compiled; camera not opened'
  exit 0
fi
"$BUILD/record" "$@"
