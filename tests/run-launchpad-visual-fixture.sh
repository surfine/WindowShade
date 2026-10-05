#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/launchpad-fidelity/shots
swiftc -DWINDOWSHADE_SDK_HAS_GLASS prototype/Core/LaunchpadModel.swift prototype/Core/NotchActivities.swift \
 prototype/Core/FlickMotion.swift tests/LaunchpadMotionStub.swift \
 prototype/App/Launchpad.swift prototype/App/LaunchpadBackdrop.swift prototype/App/LaunchpadView.swift \
 prototype/App/LaunchpadFolders.swift prototype/App/LaunchpadLibrary.swift prototype/App/LaunchpadArtwork.swift \
 prototype/App/LaunchpadToday.swift prototype/App/LaunchpadActivities.swift prototype/App/NotchActivitySymbol.swift prototype/App/LaunchpadOpenWith.swift prototype/Capture/FastCapture.swift tests/fixtures/LaunchpadVisualFixture.swift \
 -o .build/launchpad-fidelity/visual-fixture
.build/launchpad-fidelity/visual-fixture "$PWD/.build/launchpad-fidelity/shots"
