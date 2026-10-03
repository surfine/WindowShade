#!/bin/bash
# 编译 WindowShade 并原地替换现有 app bundle 里的 Mach-O，用稳定开发者证书签名。
#
# 用法：
#   ./build.sh            构建 + 签名（需要签名身份，见下）
#   ./build.sh --check    隔离优化编译与链接验证，不签名、不修改 app bundle
#   ./build.sh --stage    隔离构建到 .build/duo-validation/（发布包从这里打），写入更新清单地址 SUFeedURL
#   ./build.sh --local-parallel  本地全模块优化，使用四个后端线程；发布仍用 --stage
#
# 应用内更新（docs/update.md）：主程序链接 prototype/Vendor/Sparkle.framework（2.10.0，已删 XPCServices），
# 包里另有 Contents/Helpers/WindowShadeUpdateGuard.app（看护，源码在 Watchdog/）。嵌套代码从里往外逐个签，
# 全部用同一个身份，不用 --deep。--check 与应用一样编译并链接 Sparkle；
# 缺少该依赖时检查失败，不能把条件编译跳过接口误写成完整链接通过。
# 日常 ./build.sh 出来的开发版不写 SUFeedURL，更新器不启动，不会被线上版本换掉。
#
# 签名身份（二选一）：
#   1. 环境变量：WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
#   2. 本机未跟踪配置文件 prototype/local-codesign.env（不入 Git）：
#        WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
#   默认拒绝 ad-hoc 签名：项目希望保持 TCC 权限身份，换签名身份会重置
#   辅助功能 / 屏幕录制授权。
set -euo pipefail
cd "$(dirname "$0")"

stage_only=0
if [ "${1:-}" = "--stage" ]; then stage_only=1; fi
OPTIMIZATION_FLAGS=(-O -whole-module-optimization)
if [ "${1:-}" = "--local-parallel" ]; then OPTIMIZATION_FLAGS+=(-num-threads 4); fi
APP="WindowShade.app"
if [ "$stage_only" = "1" ]; then
  APP="$(cd .. && pwd)/.build/duo-validation/WindowShade.app"
fi
BIN="$APP/Contents/MacOS/WindowShade"
TMP_BIN="windowshade"
if [ "$stage_only" = "1" ]; then TMP_BIN="$(cd .. && pwd)/.build/duo-validation/windowshade"; fi
MODULE_CACHE="$(cd .. && pwd)/.build/module-cache"
# 更新清单地址与 EdDSA 公钥：只由 --stage 写进发布包；公钥必须和仓库 Info.plist 里的一致。
FEED_URL="https://windowshade.aaronlau.me/appcast.xml"
EXPECTED_ED_KEY="D/MZytH+oxawqKQsskoXBdwbvoPentrqfaj7Tj2pnkw="
SPARKLE_FRAMEWORK="$(pwd)/Vendor/Sparkle.framework"
SPARKLE_FLAGS=()
if [ -d "$SPARKLE_FRAMEWORK" ]; then SPARKLE_FLAGS=(-F "$(pwd)/Vendor"); fi

FRAMEWORKS=(
  -framework Cocoa
  -framework Carbon
  -framework ApplicationServices
  -framework ScreenCaptureKit
  -framework QuartzCore
  -framework CoreText
  -framework AVFoundation
  -framework Vision
  -framework ServiceManagement
  -framework Metal
  -framework MetalKit
  -framework IOKit
  -framework CoreImage
  -framework VideoToolbox
  -framework Security
  -framework CoreAudio
  -framework MapKit
  -framework LocalAuthentication
  -framework LocalAuthenticationEmbeddedUI
  -framework GameController
)

# 自动收集源文件：只扫 prototype/ 与它的模块子目录，顺序稳定（按路径排序）。
# 用 -prune 排除 app bundle、dist、.build，避免把构建产物或其它仓库内容扫进来。
# Watchdog/ 是单独编译的看护小 App，Vendor/ 是第三方框架，都不进主程序的源文件清单。
# macOS 自带 Bash 3.2 可运行（只用 find + sort + grep）。
collect_sources() {
  find . \
    -path "./WindowShade.app" -prune -o \
    -path ./dist -prune -o \
    -path ./.build -prune -o \
    -path ./Watchdog -prune -o \
    -path ./Vendor -prune -o \
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

# 编译条件探测：当前 SDK 是否带公开的 AppKit Liquid Glass API。
# 用真实头文件存在性判断，而不是猜 Swift 版本；旧 SDK 构建时玻璃分支不参与编译。
GLASS_DEFINE=""
if [ -f "$(xcrun --show-sdk-path --sdk macosx)/System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h" ]; then
  GLASS_DEFINE="-DWINDOWSHADE_SDK_HAS_GLASS"
fi
ARCH="${WINDOWSHADE_ARCH:-$(uname -m)}"
# Compile one coherent source snapshot. Edits made while a long optimized build runs
# cannot invalidate Swift inputs or mix newer shaders into the signed bundle.
mkdir -p "$(cd .. && pwd)/.build"
WORK="$(mktemp -d "$(cd .. && pwd)/.build/duo-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
COMPILE_SOURCES=()
for source in $SOURCES; do
  mkdir -p "$WORK/$(dirname "$source")"
  cp "$source" "$WORK/$source"
  COMPILE_SOURCES+=("$WORK/$source")
done
cp Effects/Duo.metal "$WORK/Duo.metal"
# 看护：Watchdog/ 下的源码（入口和它自己的菜单栏图标）加上和 App 共用的更新代码（日志、判断、换回、文案），
# 单独成一个可执行文件。共用的只有 Core/Update*.swift、App/UpdaterSystem.swift、App/UpdaterCopy.swift，
# 它们只能依赖 Foundation/AppKit 和彼此；别的 App 文件不进看护，改它们不会让 --check 的第二次类型检查失败。
mkdir -p "$WORK/Watchdog"
cp Watchdog/*.swift "$WORK/Watchdog/"
GUARD_SOURCES=()
for source in Watchdog/main.swift Watchdog/GuardIcon.swift Core/UpdateVersion.swift Core/UpdateModels.swift \
  Core/UpdateDecisions.swift App/UpdaterSystem.swift App/UpdaterCopy.swift; do
  GUARD_SOURCES+=("$WORK/$source")
done
GUARD_FRAMEWORKS=(-framework AppKit -framework Security -framework ServiceManagement)

# Original C process supervisor is compiled from the SAME isolated snapshot as Swift.
mkdir -p "$WORK/Native"
cp Native/WS2Child.c Native/WS2Child.h Native/module.modulemap "$WORK/Native/"
xcrun -sdk macosx clang -std=c11 -O2 -Wall -Wextra -Werror -target "$ARCH-apple-macosx14.0" \
  -c "$WORK/Native/WS2Child.c" -o "$WORK/WS2Child.o"
NATIVE_FLAGS=(-I "$WORK/Native" "$WORK/WS2Child.o")

# Shader checks and normal builds use the same source and deployment target.
METAL_BUILD="$(cd .. && pwd)/.build/duo-metal"
mkdir -p "$METAL_BUILD"
xcrun -sdk macosx metal -mmacosx-version-min=14.0 -fmodules-cache-path="$MODULE_CACHE" -c "$WORK/Duo.metal" -o "$WORK/Duo.air"
xcrun -sdk macosx metallib "$WORK/Duo.air" -o "$WORK/Duo.metallib"
cp "$WORK/Duo.metallib" "$METAL_BUILD/Duo.metallib"

if [ "$check_only" = "1" ]; then
  # 和发布构建用同一套编译参数（-O -whole-module-optimization），只把产物写到临时目录、不签名、
  # 不碰 app bundle。旧的 -typecheck 看不到整模块优化下才报的隔离/所有性问题（TrackpadGestures
  # 那次主线程命中测试就是 --check 通过、真构建失败），门禁要真挡住这类错误。
  echo "==> 编译验证（--check，和发布构建同样的优化参数；不签名、不修改 app bundle）"
  mkdir -p "$MODULE_CACHE"
  env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swiftc -module-cache-path "$MODULE_CACHE" -target "$ARCH-apple-macosx14.0" -O -whole-module-optimization ${GLASS_DEFINE} -o "$WORK/windowshade-check" \
      "${COMPILE_SOURCES[@]}" "${NATIVE_FLAGS[@]}" "${FRAMEWORKS[@]}" \
      "${SPARKLE_FLAGS[@]}" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
  env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swiftc -module-cache-path "$MODULE_CACHE" -target "$ARCH-apple-macosx14.0" -O -o "$WORK/WindowShadeUpdateGuard-check" \
      "${GUARD_SOURCES[@]}" "${GUARD_FRAMEWORKS[@]}"
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

if [ ! -f "$SPARKLE_FRAMEWORK/Versions/B/Sparkle" ]; then
  echo "ERROR: 缺少 prototype/Vendor/Sparkle.framework（Sparkle 2.10.0，升级流程见 DEVELOPMENT.md）。" >&2
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

echo "==> 编译"
mkdir -p "$MODULE_CACHE"
mkdir -p "$WORK/compiler-tmp"
env TMPDIR="$WORK/compiler-tmp" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -module-cache-path "$MODULE_CACHE" -target "$ARCH-apple-macosx14.0" "${OPTIMIZATION_FLAGS[@]}" ${GLASS_DEFINE} -o "$TMP_BIN" \
    "${COMPILE_SOURCES[@]}" "${NATIVE_FLAGS[@]}" "${FRAMEWORKS[@]}" \
    "${SPARKLE_FLAGS[@]}" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
echo "==> 编译看护（WindowShadeUpdateGuard）"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  swiftc -module-cache-path "$MODULE_CACHE" -target "$ARCH-apple-macosx14.0" -O -o "$WORK/WindowShadeUpdateGuard" \
    "${GUARD_SOURCES[@]}" "${GUARD_FRAMEWORKS[@]}"

if [ "$stage_only" != "1" ]; then
  echo "==> 停止这个 bundle 的 WindowShade（编译通过后才替换）"
  for task_pid in $(pgrep -x WindowShade 2>/dev/null || true); do
    task_executable=$(ps -p "$task_pid" -o comm= 2>/dev/null || true)
    if [ "$task_executable" = "$(pwd)/$BIN" ]; then kill -TERM "$task_pid" 2>/dev/null || true; fi
  done
fi
echo "==> 替换 Mach-O（保留 bundle、Info.plist、Resources）"
cp "$TMP_BIN" "$BIN"
cp "$WORK/Duo.metallib" "$APP/Contents/Resources/Duo.metallib"
cp ../docs/third-party-lock-overlay.txt "$APP/Contents/Resources/LockOverlay-LICENSE.txt"
rm -rf "$APP/Contents/Resources/ThirdParty"
# The released bundle historically carries the Swift concurrency runtime in
# Contents/Frameworks. Preserve that runtime in isolated stage builds too;
# otherwise the stage zip differs from the known-good app bundle and can fail
# before application code starts on systems without the matching toolchain.
SOURCE_FRAMEWORKS="$(pwd)/WindowShade.app/Contents/Frameworks"
if [ "$stage_only" = "1" ] && [ -d "$SOURCE_FRAMEWORKS" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$SOURCE_FRAMEWORKS/." "$APP/Contents/Frameworks/"
fi

# Sparkle：每次从 Vendor/ 重新放一份（ditto 保留符号链接），再按发布需要裁掉用不到的部分。
# 没开沙盒不需要 XPCServices；头文件和模块只给编译用；只留发布架构和 Base、zh_CN 两份本地化。
EMBED_FW="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$EMBED_FW"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$EMBED_FW"
SPARKLE_KB_BEFORE=$(du -sk "$EMBED_FW" | cut -f1)
for part in XPCServices Headers PrivateHeaders Modules; do
  rm -rf "${EMBED_FW:?}/$part" "${EMBED_FW:?}/Versions/B/$part"
done
for slice in "$EMBED_FW/Versions/B/Sparkle" "$EMBED_FW/Versions/B/Autoupdate" \
  "$EMBED_FW/Versions/B/Updater.app/Contents/MacOS/Updater"; do
  if [ "$(lipo -archs "$slice" | wc -w | tr -d ' ')" -gt 1 ]; then
    lipo -thin "$ARCH" "$slice" -output "$slice.thin"
    mv "$slice.thin" "$slice"
  fi
done
for lproj in "$EMBED_FW/Versions/B/Resources/"*.lproj; do
  case "$(basename "$lproj")" in
    Base.lproj|en.lproj|zh_CN.lproj) ;;
    *) rm -rf "$lproj" ;;
  esac
done
echo "==> Sparkle.framework：${SPARKLE_KB_BEFORE} KB → $(du -sk "$EMBED_FW" | cut -f1) KB（写进发布说明草稿）"

# 看护：LSUIElement 小 App，放在 Contents/Helpers/（Apple 给辅助程序定的位置）。
GUARD_APP="$APP/Contents/Helpers/WindowShadeUpdateGuard.app"
rm -rf "$GUARD_APP"
mkdir -p "$GUARD_APP/Contents/MacOS"
cp "$WORK/WindowShadeUpdateGuard" "$GUARD_APP/Contents/MacOS/WindowShadeUpdateGuard"
GUARD_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
GUARD_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Info.plist)
cat > "$GUARD_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>WindowShadeUpdateGuard</string>
	<key>CFBundleIdentifier</key>
	<string>com.windowshade.prototype.update-guard</string>
	<key>CFBundleName</key>
	<string>WindowShade</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${GUARD_VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${GUARD_BUILD}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

# Info.plist in the source tree owns release versions; synchronize only these
# fields so existing bundle identity and local resources remain intact.
for version_key in CFBundleShortVersionString CFBundleVersion; do
  release_value=$(/usr/libexec/PlistBuddy -c "Print $version_key" Info.plist)
  /usr/libexec/PlistBuddy -c "Set :$version_key $release_value" "$APP/Contents/Info.plist"
done
# 更新器的设置同样以源码树为准（SUFeedURL 除外：只有 --stage 写，开发版不写就不启动更新器）。
music_usage=$(plutil -extract NSAppleEventsUsageDescription xml1 -o - Info.plist)
plutil -replace NSAppleEventsUsageDescription -xml "$music_usage" "$APP/Contents/Info.plist"
for su_key in SUPublicEDKey SUVerifyUpdateBeforeExtraction SURequireSignedFeed SUEnableAutomaticChecks \
  SUScheduledCheckInterval SUAllowsAutomaticUpdates SUAutomaticallyUpdate SUEnableSystemProfiling; do
  su_value=$(plutil -extract "$su_key" xml1 -o - Info.plist)
  plutil -replace "$su_key" -xml "$su_value" "$APP/Contents/Info.plist"
done
if [ "$stage_only" = "1" ]; then
  plutil -replace SUFeedURL -string "$FEED_URL" "$APP/Contents/Info.plist"
else
  plutil -remove SUFeedURL "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> 用 Apple Development 证书签名（TCC 授权可跨重编保留）"
# 从里往外逐个签，全部同一个身份，不用 --deep：Sparkle 的安装器、Updater.app、看护都要和 App 同一个 Team，
# 否则安装器和 App 之间的连接校验不过，新版替换自己也会被“App 管理”拦下。
# 主程序照旧：不加新标志（不加 hardened runtime），标识符不变，DR 不变。
codesign --force -s "$IDENTITY" -o runtime "$EMBED_FW/Versions/B/Autoupdate"
codesign --force -s "$IDENTITY" -o runtime "$EMBED_FW/Versions/B/Updater.app"
codesign --force -s "$IDENTITY" -o runtime "$EMBED_FW"
codesign --force -s "$IDENTITY" -o runtime -i com.windowshade.prototype.update-guard "$GUARD_APP"
codesign --force -s "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

if [ "$stage_only" = "1" ]; then
  echo "==> 发布前检查：Sparkle 已链接、嵌套代码同一个 Team、更新公钥没变"
  if ! otool -L "$BIN" | grep -q "@rpath/Sparkle.framework"; then
    echo "ERROR: 主程序没有链接 Sparkle。" >&2
    exit 1
  fi
  team_of() { codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'; }
  MAIN_TEAM="$(team_of "$APP")"
  for nested in "$EMBED_FW/Versions/B/Autoupdate" "$EMBED_FW/Versions/B/Updater.app" "$EMBED_FW" "$GUARD_APP"; do
    if [ -z "$MAIN_TEAM" ] || [ "$(team_of "$nested")" != "$MAIN_TEAM" ]; then
      echo "ERROR: ${nested#"$APP"/} 的 Team 和主程序不同（${MAIN_TEAM:-无}）。" >&2
      exit 1
    fi
  done
  if [ "$(plutil -extract SUPublicEDKey raw -o - "$APP/Contents/Info.plist")" != "$EXPECTED_ED_KEY" ]; then
    echo "ERROR: SUPublicEDKey 和记下的公钥不同；换密钥要单独发一版，见 docs/update.md。" >&2
    exit 1
  fi
  # 更新器的入口要由 main.swift / WindowShade.swift 接上（见 App/UpdaterLaunch.swift、App/Updater.swift 头部注释）。
  # 少接 --self-check：安装前的试跑会拉起一整个 WindowShade；少接 recordLaunch 或 start()：新版写不了 healthy，每次更新都被换回。
  # 没接齐时只警告、不跑二进制（别的验证也用 --stage）；这样的包不能发布，DEVELOPMENT.md 的发布流程把它列为阻断项。
  UPDATER_WIRED=1
  for wiring in "main.swift:UpdateLaunch.handleEarlyArguments" "main.swift:UpdateLaunch.recordLaunch" \
    "WindowShade.swift:UpdaterController.shared.start()" "WindowShade.swift:UpdaterController.shared.applicationWillTerminate()" \
    "WindowShade.swift:UpdaterController.shared.applicationShouldTerminate()"; do
    if ! grep -qF "${wiring#*:}" "${wiring%%:*}"; then
      echo "WARNING: ${wiring%%:*} 里没有 ${wiring#*:}：更新器没接齐，这个包不能发布。" >&2
      UPDATER_WIRED=0
    fi
  done
  if [ "$UPDATER_WIRED" = "1" ]; then
    # 试跑：5 秒内返回 0，输出里有这次的 build 号（安装前的关给 10 秒；这里留余量给高负载，正常不到 1 秒）。
    STAGE_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
    if ! SELF_CHECK_OUT=$(perl -e 'alarm 5; exec @ARGV' "$BIN" --self-check 2>&1) \
      || ! printf '%s' "$SELF_CHECK_OUT" | grep -qF "build=$STAGE_BUILD"; then
      echo "ERROR: --self-check 没有在 5 秒内返回 0 并输出 build=$STAGE_BUILD：${SELF_CHECK_OUT:-无输出}" >&2
      exit 1
    fi
    echo "==> --self-check 通过：$SELF_CHECK_OUT"
  fi
fi
touch "$APP"

echo "==> 完成：$APP"
codesign -dv "$APP" 2>&1 | sed 's/^/    /'
