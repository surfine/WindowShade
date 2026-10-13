#!/bin/bash
# M12：进度零件。量 → 画法映射、数值更新不重排、结束一句、下载与拷贝用新的量、右段格子与右耳同一套。
# 纯 Foundation，不碰 AppKit 与真机。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/progress-part-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift \
  prototype/Core/WireJSON.swift prototype/Core/UsageReading.swift prototype/Core/NotchActivities.swift prototype/Core/ReleaseDefaults.swift prototype/Core/NotchSentence.swift prototype/Core/DownloadActivity.swift \
  prototype/Core/NotchRow.swift tests/ProgressPartTests.swift \
  -o .build/progress-part-tests/tests
.build/progress-part-tests/tests
