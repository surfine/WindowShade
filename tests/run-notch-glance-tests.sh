#!/bin/bash
# 看一眼从哪儿来、格子里的画面什么规矩（Core/NotchGlancePlan.swift、Core/NotchThumbnailPolicy.swift）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-glance-tests
swiftc -swift-version 6 -parse-as-library prototype/Core/NotchThumbnailPolicy.swift prototype/Core/NotchGlancePlan.swift \
  tests/NotchGlanceTests.swift -o .build/notch-glance-tests/glance
.build/notch-glance-tests/glance
