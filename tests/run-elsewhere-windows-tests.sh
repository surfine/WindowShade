#!/bin/bash
# 别的桌面上的窗口进刘海：哪些算、怎么排、写“桌面几”（docs/direction.md「回到窗口」第 1 步）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/elsewhere-windows-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/ElsewhereWindows.swift tests/ElsewhereWindowsTests.swift \
  -o .build/elsewhere-windows-tests/elsewhere
.build/elsewhere-windows-tests/elsewhere
