#!/usr/bin/env bash
#
# tools/presence-probe/run.sh
#
# 独立编译并运行只读「在场探针」。不接主 App 工程，只链接 Foundation / AVFoundation /
# Vision / AppKit。产出到 .build/presence-probe/，ad-hoc 本地签名。
#
# 只接受一种模式；observe 可另带 --camera-index=N：--capabilities（默认）/ --observe / --help。
# 绝不自动运行 --observe。

set -euo pipefail

# ---- 从脚本自身位置定位仓库根 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ---- 编译输出路径 ----
BUILD_ROOT="${REPO_ROOT}/.build/presence-probe"
APP_DIR="${BUILD_ROOT}/WindowShadePresenceProbe.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
BIN="${MACOS_DIR}/PresenceProbe"
SOURCE="${SCRIPT_DIR}/main.swift"

# ---- 严格参数校验：只接受 0 或 1 个模式参数 ----
MODE="${1:---capabilities}"
if [[ "$#" -gt 2 ]]; then exit 1; fi
case "$MODE" in
  --capabilities|--help) if [[ "$#" -gt 1 ]]; then exit 1; fi ;;
  --observe)
    if [[ "$#" -eq 2 && ! "$2" =~ ^--camera-index=[0-9]+$ ]]; then exit 1; fi ;;
  *) echo "参数错误。" >&2; exit 1 ;;
esac
if [[ "$#" -eq 0 ]]; then set -- --capabilities; fi

if [[ ! -f "${SOURCE}" ]]; then
  echo "错误: 找不到源文件 ${SOURCE}" >&2
  exit 1
fi

mkdir -p "${MACOS_DIR}"

# ---- 编译：链接 Foundation / AVFoundation / Vision / AppKit，目标 macOS 14 ----
xcrun swiftc \
  -O \
  -target "$(uname -m)-apple-macosx14.0" \
  -framework Foundation \
  -framework AVFoundation \
  -framework Vision \
  -framework AppKit \
  -o "${BIN}" \
  "${SOURCE}"

# ---- 生成最小 Info.plist，嵌入相应用途说明 ----
PLIST="${APP_DIR}/Contents/Info.plist"
cat > "${PLIST}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PresenceProbe</string>
    <key>CFBundleIdentifier</key>
    <string>me.aaronlau.WindowShade.PresenceProbe</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>WindowShadePresenceProbe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSCameraUsageDescription</key>
    <string>在场探针仅在已授权时短暂读取选定相机，用于本地人体矩形计数，不保存图像。</string>
</dict>
</plist>
PLIST

# 校验 plist 合法。
plutil -lint "${PLIST}" >/dev/null

# ---- ad-hoc 本地签名 bundle ----
codesign --force --sign - "${APP_DIR}" >/dev/null

# ---- 直接运行 bundle 内 binary，保留 stdout；不用 open ----
if [[ "${MODE}" == --observe ]]; then
  # 系统调用或 Vision 卡住时，进程的硬超时仍在 45 秒后终止探针。
  exec /usr/bin/perl -e 'alarm 45; exec @ARGV or die $!' "${BIN}" "$@"
fi
exec "${BIN}" "$@"
