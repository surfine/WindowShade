#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/paper-tests
swiftc -target "$(uname -m)-apple-macosx14.0" \
  prototype/Overlay/PaperSurfaceStyle.swift prototype/PinnedPreviewPanel.swift tests/PaperSurfaceTests.swift \
  -framework Cocoa -framework AVFoundation -o .build/paper-tests/components
.build/paper-tests/components
