#!/bin/bash
# 看一眼真机探针：需要先 `cd prototype && ./build.sh --stage`（签名隔离构建，已授权辅助功能与屏幕录制）。
# 会在屏幕上短暂出现测试窗口；不操作用户自己的窗口。
# 每次跑一项，例如 --gesture、--launchpad-keys、--fullscreen（会进一次系统全屏再退出）；完整列表见 prototype/App/GlanceProbe.swift 的调度。
# --fold-timing、--orphan（R10）、--soak [--soak-kind fold|browser|glance] [--soak-rounds N] [--soak-sample-every N]（R39）、--menubar-owner（R22）、--focus-steal（R41）、--switch-cpu、--idle-first-op [--idle-seconds N]（E6）会自行只开一扇临时窗（不必再加 --single）。
# --browser-identity（R20）：再开一个临时 App 实例，核对 orderOut 关窗与 kill -9 之后窗口浏览的列表。
# --second-display（V9）：把临时窗挪到非主屏收起再展开；--finder-columns（R23）：开一扇临时访达窗口量列表列宽，用完关掉、删掉临时文件夹；--finder-alias（R23）：临时目录里建文件夹和指向它的替身，用合成鼠标双击替身，核对访达照常打开它、没被当成窗口动作。
# --launchpad-tiling（R18）：启动台开着，往系统发 fn＋Control＋←→↑↓／F／C，对照临时 App 的参考窗，看启动台会不会被系统平铺挪动；会发真的合成键，跑的时候别碰键盘。
# --hitch [--hitch-rounds N]（规格 E3 改做法）：临时窗口收起／展开、窗口浏览开／关、看一眼出现／收回各 N 次（默认 20），每次交互量显示链接帧间隔，打印 HITCH <类> n=… ratio=… ms/s worst=… ms p95=… ms refresh=… Hz，按 Apple 卡顿预算判（真机 ratio < 5 ms/s 且 worst < 100 ms；虚拟机只拦 ≥ 500 ms 的单帧），自行只开一扇临时窗、总是带动画。
# --restore-guard（R9）：临时 App 两扇窗都收起，只展开一扇，另一扇不能冒出来、展开的那扇要在最前；--fold-unminimizable：另一扇不能最小化，核对收起前就被拒绝、没播动画、窗口原位不动。
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -n "${PROBE_SHOTS:-}" ]; then mkdir -p "$PROBE_SHOTS"; fi
FIX=.build/glance-tests/GlanceFixture.app
mkdir -p "$FIX/Contents/MacOS"
# 按支持的最低系统编（DEVELOPMENT.md「支持的系统版本」），否则默认按本机系统编，拿进 macOS 15 虚拟机就起不来。
swiftc -target arm64-apple-macos15.0 tests/fixtures/GlanceFixture.swift -o "$FIX/Contents/MacOS/GlanceFixture"
cat > "$FIX/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.windowshade.glance-fixture</string>
<key>CFBundleName</key><string>GlanceFixture</string>
<key>CFBundleExecutable</key><string>GlanceFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
codesign --force -s - "$FIX" >/dev/null 2>&1 || true
# PROBE_APP 可指向别的构建做对照（例如装好的正式版），默认是 --stage 的签名构建。
APP=${PROBE_APP:-.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade}
# 探针的「verdict」只看有没有抛异常，单项打印的 FAIL 不算数（一项 FAIL 时也会写 PASS suite）。
# 这里把输出原样打出来，任何一行以 FAIL 开头就判整次失败、非零退出。
out=$(mktemp -t glance-probe)
trap 'rm -f "$out"' EXIT
status=0
"$APP" --glance-probe --fixture "$FIX/Contents/MacOS/GlanceFixture" "$@" | tee "$out" || status=$?
if grep -q '^FAIL' "$out"; then
  echo "FAIL run-glance-probe: $(grep -c '^FAIL' "$out") 项 FAIL（verdict 那一行不算数）" >&2
  exit 1
fi
exit "$status"
