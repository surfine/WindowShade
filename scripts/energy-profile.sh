#!/bin/bash
# 静置能耗例行项（规格 E1）与内存口径（规格 E2）：每版发布前在同一台机器上跑，数字进 docs/scorecard.md。
# 口径固定：启动 App 后先等 20 秒（开机动作做完），再静置 60 秒不碰鼠标键盘；
# CPU% = 这 60 秒里进程累计 CPU 时间 / 60 秒；跑 3 次取中位数。
# 内存同时记两种，别混着比：phys_footprint（活动监视器「内存」那一列）和 RSS（常驻页，含共享库）。
# 用法：scripts/energy-profile.sh [App 可执行文件]（默认 .build/duo-validation 的签名构建）
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${1:-.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade}"
[ -x "$BIN" ] || { echo "NOT RUN: 没有 $BIN（先 cd prototype && ./build.sh --stage）"; exit 78; }
if pgrep -x WindowShade >/dev/null; then echo "NOT RUN: 已经有 WindowShade 在跑，先退出它"; exit 78; fi
cpu_seconds() { ps -o time= -p "$1" | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }
results=()
for run in 1 2 3; do
  "$BIN" > /dev/null 2>&1 & pid=$!
  sleep 20
  start=$(cpu_seconds "$pid")
  sleep 60
  end=$(cpu_seconds "$pid")
  pct=$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.2f", (b - a) / 60 * 100 }')
  foot=$(footprint "$pid" 2>/dev/null | sed -n 's/.*Footprint: \([0-9.]* [KMG]*B\).*/\1/p' | head -1)
  rss=$(ps -o rss= -p "$pid" | awk '{ printf "%.1f MB", $1/1024 }')
  echo "run $run: cpu=${pct}% phys_footprint=${foot:-?} rss=${rss}"
  results+=("$pct")
  kill "$pid"; wait "$pid" 2>/dev/null || true
  sleep 3
done
median=$(printf '%s\n' "${results[@]}" | sort -n | sed -n 2p)
echo "idle CPU median of 3 × 60 s: ${median}%  ($(sw_vers -productVersion), $(sysctl -n hw.model), build $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$(dirname "$BIN")/../Info.plist"))"
