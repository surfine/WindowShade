#!/usr/bin/env bash
#
# tools/accessory-probe/run.sh
#
# 独立编译并运行蓝牙配件探针。不接触主 App 工程，只链接 Foundation 与 IOBluetooth。
# 默认使用 --summary；调用者参数原样透传。
# 只编译一个普通可执行文件，不做 codesign。

set -euo pipefail

# ---- 从脚本自身位置定位仓库根 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ---- 编译输出路径 ----
BUILD_DIR="${REPO_ROOT}/.build/accessory-probe"
BIN="${BUILD_DIR}/AccessoryProbe"
SOURCE="${SCRIPT_DIR}/main.swift"

if [[ ! -f "${SOURCE}" ]]; then
  echo "错误: 找不到源文件 ${SOURCE}" >&2
  exit 1
fi

mkdir -p "${BUILD_DIR}"

# ---- 编译：普通可执行文件，无需签名 ----
xcrun swiftc \
  -O \
  -target "$(uname -m)-apple-macosx14.0" \
  -framework Foundation \
  -framework IOBluetooth \
  -o "${BIN}" \
  "${SOURCE}"

# ---- 直接运行 binary，保留 stdout；不用 open ----
if [[ "$#" -eq 0 ]]; then
  set -- --summary
fi

exec "${BIN}" "$@"
