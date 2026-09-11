#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/duo-tests .build/duo-metal
swiftc prototype/Effects/FoldDriver.swift prototype/Effects/EffectFrameAwaiter.swift prototype/Effects/LatestEffectFrame.swift prototype/Effects/RestoreVerifier.swift prototype/Recovery/DurableShadeJournal.swift tests/DuoCoreTests.swift -o .build/duo-tests/core
.build/duo-tests/core
swiftc prototype/Effects/FoldDriver.swift prototype/Effects/EffectFrameAwaiter.swift prototype/Effects/LatestEffectFrame.swift prototype/Effects/EffectFrameSource.swift tests/DuoFrameMetadataTests.swift -framework Cocoa -framework ScreenCaptureKit -o .build/duo-tests/frame-metadata
.build/duo-tests/frame-metadata
python3 tests/duo-integration-check.py
xcrun -sdk macosx metal -mmacosx-version-min=14.0 -c prototype/Effects/Duo.metal -o .build/duo-metal/Duo.air
xcrun -sdk macosx metallib .build/duo-metal/Duo.air -o .build/duo-metal/Duo.metallib
xcrun -sdk macosx metal -mmacosx-version-min=14.0 -c tests/fixtures/DuoBook-fd7b0fc.metal -o .build/duo-tests/upstream.air
xcrun -sdk macosx metallib .build/duo-tests/upstream.air -o .build/duo-tests/upstream.metallib
swiftc -O prototype/Effects/FoldDriver.swift tests/DuoShaderOracle.swift -framework Metal -o .build/duo-tests/shader-oracle
.build/duo-tests/shader-oracle
