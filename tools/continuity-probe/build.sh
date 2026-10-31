#!/bin/bash
# Builds the probe with an embedded Info.plist (needed for the Bluetooth TCC prompt). Usage: build.sh OUTPUT
set -euo pipefail
cd "$(dirname "$0")"
swiftc -O -swift-version 5 ContinuityProbe.swift -o "${1:?output path}" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist -framework CoreBluetooth
