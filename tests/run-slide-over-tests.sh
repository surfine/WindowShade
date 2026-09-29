#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/slide-over-tests
swiftc prototype/Core/TrackpadGesture.swift prototype/Core/ArrangeGap.swift prototype/Core/FlickMotion.swift prototype/Core/SlideOverMotion.swift tests/SlideOverMotionTests.swift -o .build/slide-over-tests/motion
.build/slide-over-tests/motion
