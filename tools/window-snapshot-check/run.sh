#!/usr/bin/env bash
#
# tools/window-snapshot-check/run.sh
#
# 编译并运行窗口快照检查：自己开一扇小窗口，分别在屏上、最小化后、退到屏外三种状态下
# 用 WindowSnapshot 截它，看画面拿不拿得到。不接触主 App 工程。
# 只编译一个普通可执行文件，不做 codesign。

set -euo pipefail

# 从仓库根运行，保证源文件路径固定。
cd "$(dirname "$0")/../.."

BUILD_DIR=".build/window-snapshot-check"
mkdir -p "${BUILD_DIR}"

swiftc -O -swift-version 6 -parse-as-library \
  prototype/Capture/WindowSnapshot.swift \
  tools/window-snapshot-check/main.swift \
  -o "${BUILD_DIR}/check"

exec "${BUILD_DIR}/check"
