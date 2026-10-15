#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/paper-tests
swiftc -target "$(uname -m)-apple-macosx14.0" \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/FlickMotion.swift prototype/Core/NotchLevelEars.swift prototype/Core/NotchLevelStep.swift prototype/Core/NotchLevelGate.swift prototype/Core/NotchLevelSuppression.swift prototype/App/Motion.swift \
  prototype/Overlay/SystemAppearance.swift prototype/Overlay/PaperSurfaceStyle.swift prototype/Overlay/PreviewSurfaces.swift prototype/PinnedPreviewPanel.swift tests/PaperSurfaceTests.swift \
  -framework Cocoa -framework AVFoundation -o .build/paper-tests/components
.build/paper-tests/components
