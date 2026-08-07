#!/bin/bash
# 编译 WindowShade 并原地替换现有 app bundle 里的 Mach-O，用稳定开发者证书签名。
#
# 用法：
#   ./build.sh            构建 + 签名（需要签名身份，见下）
#   ./build.sh --check    仅编译验证（swiftc typecheck），不签名、不修改 app bundle
#
# 签名身份（二选一）：
#   1. 环境变量：WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
#   2. 本机未跟踪配置文件 prototype/local-codesign.env（不入 Git）：
#        WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
#   默认拒绝 ad-hoc 签名：项目希望保持 TCC 权限身份，换签名身份会重置
#   辅助功能 / 屏幕录制授权。
set -euo pipefail
cd "$(dirname "$0")"

APP="WindowShade.app"
BIN="$APP/Contents/MacOS/WindowShade"
TMP_BIN="windowshade"
MODULE_CACHE="$(cd .. && pwd)/.build/module-cache"

FRAMEWORKS=(
  -framework Cocoa
  -framework Carbon
  -framework ApplicationServices
  -framework ScreenCaptureKit
  -framework QuartzCore
  -framework CoreText
  -framework AVFoundation
  -framework ServiceManagement
)

# 自动收集源文件：只扫 prototype/ 与它的模块子目录，顺序稳定（按路径排序）。
# 用 -prune 排除 app bundle、dist、.build，避免把构建产物或其它仓库内容扫进来。
# macOS 自带 Bash 3.2 可运行（只用 find + sort + grep）。
collect_sources() {
  find . \
    -path "./$APP" -prune -o \
    -path ./dist -prune -o \
    -path ./.build -prune -o \
    -name '*.swift' -print \
    | sed 's|^\./||' \
    | sort
}

check_only=0
if [ "${1:-}" = "--check" ]; then
  check_only=1
fi

# 签名身份：环境变量优先，其次本机未跟踪配置文件。
IDENTITY="${WINDOWSHADE_CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && [ -f local-codesign.env ]; then
  # shellcheck disable=SC1091
  source local-codesign.env
  IDENTITY="${WINDOWSHADE_CODESIGN_IDENTITY:-}"
fi

SOURCES="main.swift $(collect_sources | grep -v '^main.swift$')"
echo "==> 源文件：$(collect_sources | wc -l | tr -d ' ') 个 Swift 文件"

if [ "$check_only" = "1" ]; then
  echo "==> 编译验证（--check，不签名、不修改 app bundle）"
  mkdir -p "$MODULE_CACHE"
  env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swiftc -typecheck $SOURCES "${FRAMEWORKS[@]}"
  echo "==> 编译验证通过"
  exit 0
fi

if [ -z "$IDENTITY" ]; then
  echo "ERROR: 未提供签名身份。请设置 WINDOWSHADE_CODESIGN_IDENTITY，或创建" >&2
  echo "       prototype/local-codesign.env（该文件不提交进 Git）。拒绝 ad-hoc" >&2
  echo "       签名，避免重置 TCC 授权。" >&2
  exit 1
fi

if ! security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
  echo "ERROR: 未找到签名身份 ${IDENTITY}；拒绝 ad-hoc 签名，避免重置 TCC 授权。" >&2
  exit 1
fi

# 没有现成 bundle 时，用仓库里的 Info.plist + app icon bootstrap 一个最小 bundle。
# 全新 clone 没有旧 TCC 权限需要保护，所以不必要求先下载一份预编译 binary；
# 已有 bundle 则继续原地替换 Mach-O，保留 TCC 身份。
if [ ! -d "$APP/Contents/MacOS" ]; then
  echo "==> 未找到现有 ${APP}，从源码仓库资源 bootstrap 最小 bundle"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp Info.plist "$APP/Contents/Info.plist"
  if [ -f ../assets/app-icon/WindowShade.icns ]; then
    cp ../assets/app-icon/WindowShade.icns "$APP/Contents/Resources/WindowShade.icns"
  else
    echo "WARNING: assets/app-icon/WindowShade.icns 缺失，bundle 将没有 app icon" >&2
  fi
fi

echo "==> 停止正在运行的 WindowShade（避免运行中替换 Mach-O 触发 TCC 混乱）"
pkill -x WindowShade 2>/dev/null || true

echo "==> 编译"
mkdir -p "$MODULE_CACHE"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -O -o "$TMP_BIN" $SOURCES "${FRAMEWORKS[@]}"

echo "==> 替换 Mach-O（保留 bundle、Info.plist、Resources）"
cp "$TMP_BIN" "$BIN"

echo "==> 用 Apple Development 证书签名（TCC 授权可跨重编保留）"
codesign --force -s "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
touch "$APP"

echo "==> 完成：$(pwd)/$APP"
codesign -dv "$APP" 2>&1 | sed 's/^/    /'
