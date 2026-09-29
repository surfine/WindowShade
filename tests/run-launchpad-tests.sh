#!/bin/bash
# 启动台模型：纯规则（格子、翻页、搜索、拖放、文件夹、资料库）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/launchpad-tests
swiftc prototype/Core/LaunchpadModel.swift tests/LaunchpadModelTests.swift -o .build/launchpad-tests/model
.build/launchpad-tests/model
