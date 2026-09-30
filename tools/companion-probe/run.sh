#!/usr/bin/env bash
#
# tools/companion-probe/run.sh
#
# 独立编译并运行 WindowShade companion 认证能力探针。
# 不接触主 App 工程，只链接 Cocoa / LocalAuthentication。
#
# 默认只运行 --capabilities；原样透传调用者传入的参数。
# 绝不自动运行 --authenticate。

set -euo pipefail

# ---- 从脚本自身位置定位仓库根 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ---- 编译输出路径 ----
BUILD_ROOT="${REPO_ROOT}/.build/companion-probe"
APP_DIR="${BUILD_ROOT}/WindowShadeCompanionProbe.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
BIN="${MACOS_DIR}/CompanionProbe"
SOURCE="${SCRIPT_DIR}/main.swift"

echo "== 构建 companion 探针 =="
echo "仓库根: ${REPO_ROOT}"
echo "源文件: ${SOURCE}"

if [[ ! -f "${SOURCE}" ]]; then
  echo "错误: 找不到源文件 ${SOURCE}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"

# ---- 编译：只链接 Cocoa 与 LocalAuthentication ----
echo "编译中..."
xcrun swiftc \
  -O \
  -target "$(uname -m)-apple-macosx14.0" \
  -framework Cocoa \
  -framework LocalAuthentication \
  -o "${BIN}" \
  "${SOURCE}"

# ---- 生成最小 Info.plist ----
PLIST="${APP_DIR}/Contents/Info.plist"
cat > "${PLIST}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>CompanionProbe</string>
    <key>CFBundleIdentifier</key>
    <string>me.aaronlau.WindowShade.CompanionProbe</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>WindowShadeCompanionProbe</string>
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
</dict>
</plist>
PLIST

# 校验 plist 合法。
plutil -lint "${PLIST}" >/dev/null

# ---- ad-hoc 签名 bundle ----
echo "ad-hoc 签名 bundle..."
codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 \
  || codesign --force --deep --sign - "${APP_DIR}" >/dev/null

# ---- 直接运行 bundle 内 binary，保留 stdout；不用 open ----
# 默认只运行 --capabilities；若调用者给了参数则原样透传。
if [[ "$#" -eq 0 ]]; then
  set -- --capabilities
fi

echo "运行: ${BIN} $*"
echo "----------------------------------------"
exec "${BIN}" "$@"
