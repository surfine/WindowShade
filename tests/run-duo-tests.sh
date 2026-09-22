#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/duo-tests .build/duo-metal
swiftc prototype/Effects/FoldDriver.swift prototype/Effects/EffectFrameAwaiter.swift prototype/Effects/LatestEffectFrame.swift prototype/Effects/RestoreVerifier.swift prototype/Core/FoldVerifier.swift prototype/Core/TitlebarTripleClickIntent.swift prototype/Recovery/DurableShadeJournal.swift tests/DuoCoreTests.swift -o .build/duo-tests/core
.build/duo-tests/core
swiftc prototype/Effects/FoldDriver.swift prototype/Effects/EffectFrameAwaiter.swift prototype/Effects/LatestEffectFrame.swift prototype/Effects/EffectFrameSource.swift prototype/Capture/CaptureIndicatorRemoval.swift tests/DuoFrameMetadataTests.swift -framework Cocoa -framework ScreenCaptureKit -o .build/duo-tests/frame-metadata
.build/duo-tests/frame-metadata
python3 tests/duo-integration-check.py
xcrun -sdk macosx metal -mmacosx-version-min=14.0 -c prototype/Effects/Duo.metal -o .build/duo-metal/Duo.air
xcrun -sdk macosx metallib .build/duo-metal/Duo.air -o .build/duo-metal/Duo.metallib
