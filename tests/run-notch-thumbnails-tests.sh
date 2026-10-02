#!/bin/bash
# 刘海格子缩略图（App/NotchThumbnails.swift）：一次抓几张、多久重抓、作废后丢结果。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-thumbnails-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/NotchThumbnailPolicy.swift prototype/App/NotchThumbnails.swift \
  tests/support/NotchThumbnailsShim.swift tests/NotchThumbnailsTests.swift \
  -o .build/notch-thumbnails-tests/run
.build/notch-thumbnails-tests/run
