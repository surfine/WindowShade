#!/bin/bash
# 画中画的大小、吸附到角、推到边上藏起来、只看一块的换算（纯逻辑，不操作任何窗口）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/pip-layout-tests
swiftc -parse-as-library prototype/Core/PiPLayout.swift prototype/Core/FlickMotion.swift \
  tests/PiPLayoutTests.swift -o .build/pip-layout-tests/pip
.build/pip-layout-tests/pip
