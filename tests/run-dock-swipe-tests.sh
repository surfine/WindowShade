#!/bin/bash
# Dock 图标上的两指上下滑：判定（纯逻辑，不碰 Dock、不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/dock-swipe-tests
swiftc -parse-as-library prototype/Core/DockSwipeTrack.swift tests/DockSwipeTests.swift -o .build/dock-swipe-tests/dock-swipe
.build/dock-swipe-tests/dock-swipe
