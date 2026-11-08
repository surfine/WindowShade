#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p validation .build
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
 reference/prototype/Core/Contracts.swift overlay/prototype/Core/CodexWire.swift \
 overlay/prototype/Core/FocusTimer.swift overlay/prototype/Core/WS2CompanionFrame.swift \
 overlay/prototype/Core/WS2ApprovalReview.swift overlay/prototype/Core/WS2DeviceInputGate.swift \
 overlay/prototype/Core/WS2FocusWindowOwnership.swift tests/CoreTests.swift -o .build/part4-core-tests
.build/part4-core-tests "$PWD/validation" | tee validation/core-tests.txt
