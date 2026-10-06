#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/activity-frame-probe
swiftc -O -target "$(uname -m)-apple-macosx14.0" \
  prototype/Core/NotchActivities.swift prototype/Core/FlickMotion.swift prototype/App/Motion.swift \
  prototype/App/NotchActivityPollPolicy.swift prototype/App/NotchActivitySymbol.swift prototype/App/NotchActivitySources.swift prototype/App/NotchActivityController.swift prototype/App/NotchActivityView.swift \
  tools/activity-frame-probe/main.swift -framework Cocoa -framework QuartzCore -framework CoreAudio -framework MapKit -framework Carbon \
  -o .build/activity-frame-probe/probe
exec .build/activity-frame-probe/probe
