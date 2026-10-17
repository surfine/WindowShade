#!/bin/bash
# 讲解动画（SettingsExplainer）：令牌时长、一轮时长、关键帧、读屏句、页 / 行 / 选项 / 关着的状态机、6 轮上限、
# 看不见时停、截图定帧、箭头路径（纯逻辑，不开窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/explainer-tests
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/WSL10n.swift prototype/Core/PrivacyPaneName.swift prototype/Core/FlickMotion.swift \
  prototype/Core/ExplainerScript.swift "prototype/Core/ExplainerScenes+Common.swift" "prototype/Core/ExplainerScenes+Gestures.swift" "prototype/Core/ExplainerScenes+Shade.swift" \
  tests/ExplainerTests.swift -o .build/explainer-tests/explainer
.build/explainer-tests/explainer
