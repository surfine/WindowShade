#!/bin/bash
# E3：对一个构建跑一轮卡顿记录（Animation Hitches 只记 15 秒，期间按 4 次 ⌃⌘C：收起、展开各 2 次）。
# 用法：bash tests/e3/run-one.sh <new|old> <轮号> [输出目录]
#   new = 当前签名构建（带 -InstallHistory 1，让 ⌃⌘C 生效，不写用户偏好）；old = 1.0.15
#   跑完一个构建的几轮后：python3 tests/e3/summarize.py report <输出目录>  → 输出目录/summary.md
# 环境变量：
#   E3_NEW_APP   新构建 .app（默认 <主仓库>/.build/duo-validation/WindowShade.app）
#   E3_OLD_APP   1.0.15 的 .app（默认 e3 暂存目录里那份）
#   E3_ATTACH    attach（默认，失败自动退到 all）| all（--all-processes，摘要里按进程名过滤）
#   E3_IDLE_SECS 要求用户空闲多少秒才开始（默认 60）；E3_IDLE_WAIT_MIN 最多等多少分钟（默认 30）
# 铁律：每次只开一个 xctrace；录制 ≤15 秒；导出成 XML 后立刻删 .trace；可用空间 <15 GB 不开始、录制中跌破就杀掉。
set -uo pipefail
WHICH=${1:?new|old}; RUN=${2:?run number}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
MAIN=$(cd "$(git -C "$REPO" rev-parse --git-common-dir)/.." && pwd)
S=/private/tmp/claude-501/-Users-aaron-Documents-WindowShade/e20dabbb-f268-4ba8-9581-ffaab367e5e6/scratchpad/e3
OUT=${3:-$S/out}; mkdir -p "$OUT"
WORK="$OUT/work"; mkdir -p "$WORK"
TAG=$WHICH-$RUN
MIN_FREE_GB=15; LIMIT=15; PRESSES=4; GAP=2.5
case $WHICH in
  new) APP=${E3_NEW_APP:-$MAIN/.build/duo-validation/WindowShade.app}; EXTRA=(-InstallHistory 1) ;;
  old) APP=${E3_OLD_APP:-$S/v1015/WindowShade.app}; EXTRA=() ;;
  *) echo "usage: run-one.sh <new|old> <run> [outdir]"; exit 64 ;;
esac
[ -x "$APP/Contents/MacOS/WindowShade" ] || { echo "ABORT: no app at $APP"; exit 66; }

free_gb() { df -g /System/Volumes/Data | awk 'NR==2 {print $4}'; }
idle() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1e9); exit}'; }
[ "$(free_gb)" -ge $MIN_FREE_GB ] || { echo "ABORT: only $(free_gb) GB free on /System/Volumes/Data (< $MIN_FREE_GB)"; df -h /System/Volumes/Data; exit 3; }
pgrep -x xctrace >/dev/null && { echo "ABORT: another xctrace is running"; exit 4; }
[ -z "${E3_ALLOW_OTHER:-}" ] && pgrep -x WindowShade >/dev/null && { echo "ABORT: another WindowShade is running (hotkey clash); quit it or set E3_ALLOW_OTHER=1"; exit 4; }

APID=""; FPID=""; XPID=""; WPID=""
cleanup() {
  [ -n "$WPID" ] && kill "$WPID" 2>/dev/null
  [ -n "$XPID" ] && kill -INT "$XPID" 2>/dev/null
  [ -n "$FPID" ] && kill "$FPID" 2>/dev/null
  [ -n "$APID" ] && kill "$APID" 2>/dev/null
  sleep 1; rm -rf "$OUT/$TAG.trace"
}
trap cleanup EXIT

# 夹具与按键工具：编一次放在 work 里（和 run-glance-probe.sh 同一个编法）
FIX="$WORK/GlanceFixture.app"
if [ ! -x "$FIX/Contents/MacOS/GlanceFixture" ]; then
  mkdir -p "$FIX/Contents/MacOS"
  swiftc -target arm64-apple-macos15.0 "$REPO/tests/fixtures/GlanceFixture.swift" -o "$FIX/Contents/MacOS/GlanceFixture" || { echo "ABORT: fixture build failed"; exit 5; }
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
fi
PRESS="$WORK/press-toggle"
[ -x "$PRESS" ] || swiftc -O "$HERE/press-toggle.swift" -o "$PRESS" || { echo "ABORT: press-toggle build failed"; exit 5; }

# 等用户空闲（鼠标键盘都不动），否则按键会和人抢
need=${E3_IDLE_SECS:-60}
for _ in $(seq "${E3_IDLE_WAIT_MIN:-30}"); do [ "$(idle)" -ge "$need" ] && break; sleep 60; done
[ "$(idle)" -ge "$need" ] || { echo "ABORT: user not idle ${need}s"; exit 2; }

VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null)
{
  echo "run=$TAG version=$VER app=$APP start=$(date '+%F %T') idle=$(idle)s loadavg=$(sysctl -n vm.loadavg) free_gb=$(free_gb) macos=$(sw_vers -productVersion)"
  echo "codesign=$(codesign -dv "$APP" 2>&1 | grep -E 'flags=' | sed 's/.*flags=//')"
} | tee "$OUT/$TAG.meta"

"$APP/Contents/MacOS/WindowShade" ${EXTRA[@]+"${EXTRA[@]}"} >"$OUT/$TAG.app.log" 2>&1 &
APID=$!
sleep 5
"$FIX/Contents/MacOS/GlanceFixture" --single >"$OUT/$TAG.fix.log" 2>&1 &
FPID=$!
sleep 3
kill -0 "$APID" 2>/dev/null || { echo "ABORT: app exited at launch (see $OUT/$TAG.app.log)"; exit 6; }
echo "app_pid=$APID fixture_pid=$FPID" | tee -a "$OUT/$TAG.meta"

record() {  # $1 = attach|all
  rm -rf "$OUT/$TAG.trace"
  if [ "$1" = attach ]; then
    xcrun xctrace record --template "Animation Hitches" --attach "$APID" --time-limit ${LIMIT}s --output "$OUT/$TAG.trace" >"$OUT/$TAG.xctrace.log" 2>&1 &
  else
    xcrun xctrace record --template "Animation Hitches" --all-processes --time-limit ${LIMIT}s --output "$OUT/$TAG.trace" >"$OUT/$TAG.xctrace.log" 2>&1 &
  fi
  XPID=$!
  # 看门狗：可用空间跌破阈值就停掉录制
  ( while kill -0 "$XPID" 2>/dev/null; do
      [ "$(free_gb)" -lt $MIN_FREE_GB ] && { echo "WATCHDOG: free space < $MIN_FREE_GB GB, stopping xctrace" >>"$OUT/$TAG.xctrace.log"; kill -INT "$XPID"; sleep 3; kill -9 "$XPID" 2>/dev/null; break; }
      sleep 1
    done ) &
  WPID=$!
}
MODE=${E3_ATTACH:-attach}
record "$MODE"
sleep 3
if [ "$MODE" = attach ] && ! kill -0 "$XPID" 2>/dev/null; then
  echo "INFO attach failed ($(tail -n1 "$OUT/$TAG.xctrace.log")); falling back to --all-processes" | tee -a "$OUT/$TAG.meta"
  kill "$WPID" 2>/dev/null; MODE=all; record all; sleep 3
fi
echo "record_mode=$MODE" | tee -a "$OUT/$TAG.meta"
"$PRESS" "$FPID" $PRESSES $GAP >"$OUT/$TAG.press.log" 2>&1
wait "$XPID"; XRC=$?
kill "$WPID" 2>/dev/null; WPID=""; XPID=""
echo "end idle=$(idle)s loadavg=$(sysctl -n vm.loadavg) xctrace_rc=$XRC free_gb=$(free_gb)" | tee -a "$OUT/$TAG.meta"
kill "$FPID" 2>/dev/null; kill "$APID" 2>/dev/null; FPID=""; APID=""

# 导出后立刻删 .trace，再读 XML 出摘要
if [ -d "$OUT/$TAG.trace" ]; then
  python3 -I "$HERE/summarize.py" export "$OUT/$TAG.trace" "$OUT/$TAG.xml" | tee -a "$OUT/$TAG.meta"
else
  echo "FAIL no trace produced (see $OUT/$TAG.xctrace.log)"
fi
rm -rf "$OUT/$TAG.trace"
if [ -f "$OUT/$TAG.xml/hitches.xml" ]; then
  python3 -I "$HERE/summarize.py" summarize "$OUT/$TAG.xml" "$TAG" "$OUT" --process WindowShade --press-log "$OUT/$TAG.press.log" --meta "$OUT/$TAG.meta"
  python3 -I "$HERE/summarize.py" report "$OUT"
  ( cd "$OUT" && tar czf "$TAG.xml.tgz" "$TAG.xml" && rm -rf "$TAG.xml" )
else
  echo "FAIL $TAG: no hitches table exported"; exit 7
fi
