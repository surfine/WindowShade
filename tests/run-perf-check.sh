#!/bin/bash
# 性能复检（要解锁的图形会话；机器最好空着）。把「解锁后该看的东西」收成一条命令：
#   1) 锁屏就先退出，别在锁屏下误判（GUI 探针在锁屏会以 posErr=-25205 失败）；
#   2) 停掉 /Applications 那份实例（同 bundle id 会互相抢 AX），跑收起计时；
#   3) 量 60 秒空闲 CPU（效果开着），和已知基线并排打印；
#   4) 从日志里挑出本轮关心的三类行：lid: poll / perf: fold install / main-thread stall；
#   5) 不管成功失败，把 /Applications 的应用重新启动。
set -euo pipefail
cd "$(dirname "$0")/.."
LOG="${WINDOWSHADE_LOG_PATH:-/tmp/windowshade.log}"
APP=/Applications/WindowShade.app
STAGE=.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade

front=$(lsappinfo front 2>/dev/null || true)
if lsappinfo info -only name "$front" 2>/dev/null | grep -q loginwindow; then
  # 退出码 0：这是需要图形会话的手工复检，锁屏下跳过不该让「跑一遍全部 runner」变红。
  echo "SKIP: 屏幕锁着，GUI 探针在这个状态下会以 kAXErrorCannotComplete 失败；解锁后再跑。"
  exit 0
fi
[ -x "$STAGE" ] || { echo "SKIP: 没有签名隔离构建；先在 prototype/ 跑 ./build.sh --stage"; exit 0; }

restore() { open "$APP" >/dev/null 2>&1 || true; }
trap restore EXIT

echo "== 收起计时（签名隔离构建；会折叠测试用的临时窗口）"
pkill -f "WindowShade.app/Contents/MacOS/WindowShade" 2>/dev/null || true
sleep 1
bash tests/run-glance-probe.sh --single --fold-timing 2>&1 | grep -E "TIMING|FAIL" || true

echo
echo "== 空闲 CPU（效果照当前设置；基线：开着 1.16–1.32%、关掉 0.31%、锁屏空闲 0.04%）"
open "$APP"
sleep 8
pid=$(pgrep -f "Applications/WindowShade.app/Contents/MacOS/WindowShade" | head -1)
if [ -n "$pid" ]; then
  top -l 61 -s 1 -pid "$pid" -stats cpu \
    | grep -E '^[[:space:]]*[0-9.]+[[:space:]]*$' \
    | awk '{s+=$1; n++; if ($1>m) m=$1} END {printf "空闲 60 秒平均 %.2f%%（峰值 %.1f%%，样本 %d）\n", s/n, m, n}'
else
  echo "应用没起来，跳过 CPU"
fi

echo
echo "== 日志里该看的（最近 200 行）"
tail -200 "$LOG" | grep -aE "lid: poll|perf: fold install|main-thread stall sample|main-thread tracking" | tail -20 || echo "（还没有这些行：先真的折叠/合盖一次）"
