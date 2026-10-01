#!/bin/bash
# 启动台的无头性能基准：扫描 / 初始排列 / 每一页与分类的布局各花多久。
# 只计时，不截图、不写用户的排列；锁屏也能跑。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/launchpad-perf
swiftc -DWINDOWSHADE_SDK_HAS_GLASS prototype/Core/LaunchpadModel.swift prototype/Core/NotchActivities.swift \
 prototype/App/Launchpad.swift prototype/App/LaunchpadBackdrop.swift prototype/App/LaunchpadView.swift \
 prototype/App/LaunchpadFolders.swift prototype/App/LaunchpadLibrary.swift prototype/App/LaunchpadArtwork.swift \
 prototype/App/LaunchpadToday.swift prototype/App/LaunchpadActivities.swift prototype/App/NotchActivitySymbol.swift \
 prototype/App/LaunchpadOpenWith.swift tests/fixtures/LaunchpadPerfFixture.swift \
 -o .build/launchpad-perf/perf
.build/launchpad-perf/perf
