#!/bin/bash
# 看一眼真机探针：需要先 `cd prototype && ./build.sh --stage`（签名隔离构建，已授权辅助功能与屏幕录制）。
# 会在屏幕上短暂出现测试窗口；不操作用户自己的窗口。
# 每次跑一项，例如 --gesture、--launchpad-keys、--fullscreen（会进一次系统全屏再退出）；完整列表见 prototype/App/GlanceProbe.swift 的调度。
# --fold-timing、--orphan（R10）、--soak [--soak-rounds N]（R39）、--menubar-owner（R22）、--focus-steal（R41）、--switch-cpu、--idle-first-op [--idle-seconds N]（E6）会自行只开一扇临时窗（不必再加 --single）。
# --browser-identity（R20）：再开一个临时 App 实例，核对 orderOut 关窗与 kill -9 之后窗口浏览的列表。
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -n "${PROBE_SHOTS:-}" ]; then mkdir -p "$PROBE_SHOTS"; fi
FIX=.build/glance-tests/GlanceFixture.app
mkdir -p "$FIX/Contents/MacOS"
swiftc tests/fixtures/GlanceFixture.swift -o "$FIX/Contents/MacOS/GlanceFixture"
cat > "$FIX/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.windowshade.glance-fixture</string>
<key>CFBundleName</key><string>GlanceFixture</string>
<key>CFBundleExecutable</key><string>GlanceFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
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
