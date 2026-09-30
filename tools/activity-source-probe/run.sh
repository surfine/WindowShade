#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build/activity-source-probe
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx14.0" \
 prototype/Core/NotchActivities.swift prototype/App/NotchActivitySources.swift tools/activity-source-probe/main.swift \
 -framework Cocoa -framework Carbon -framework CoreAudio -o .build/activity-source-probe/probe
exec .build/activity-source-probe/probe
