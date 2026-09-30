#!/bin/bash
# 阶段 1B：真锁屏小窗口实验（独立可执行，不进 App）。要人蹲在旁边。
#
#   bash tests/run-lock-probe.sh                 只查私有符号在不在（安全：不建空间、不动窗口、不锁屏）
#   bash tests/run-lock-probe.sh --level-only    对照组：同样的窗口，只提高层级，不调空间 API
#   bash tests/run-lock-probe.sh --space         实验组：上游的私有空间配方（**未核定的 ABI**）
#
# 加 --pre-create 表示锁屏前就把窗口建好；不加就是确认锁上之后再建。--seconds 90 控制在锁屏上待多久。
#
# 做实验前先读 tools/lock-probe/main.swift 顶部的安全规矩。要点：
# - 探针非 key、非 main、整窗鼠标穿透，放屏幕右上角，不挡认证；
# - 自己到期撤场，外面还有一层父进程硬超时（perl alarm，不需要 root）；
# - **探针绝不尝试解锁**：锁由你按 ⌃⌘Q，解锁用系统认证。
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=.build/lock-probe
mkdir -p "$WORK"
swiftc -O tools/lock-probe/main.swift -o "$WORK/lock-probe"

if [ $# -eq 0 ]; then
  exec "$WORK/lock-probe"
fi

SECONDS_ON_SCREEN=90
WAIT_FOR_LOCK=180
# 只读一遍参数、不消费它们（探针自己还要解析）：父进程的硬超时按这里算。
previous=""
for argument in "$@"; do
  case "$previous" in
    --seconds) SECONDS_ON_SCREEN="$argument" ;;
    --wait) WAIT_FOR_LOCK="$argument" ;;
  esac
  previous="$argument"
done

echo "==> 真锁屏实验要开始了。你接下来要做的："
echo "    1) 等探针提示后按 ⌃⌘Q 把屏幕锁上；"
echo "    2) 看屏幕右上角有没有一个黑色小条在数数（$( [ "$1" = "--level-only" ] && echo "这个对照组只看它能不能越过锁屏" || echo "这就是要验的东西" )）；"
echo "    3) 看完用系统认证解锁；探针看到解锁会自己撤场。"
echo "    全程最多约 $((SECONDS_ON_SCREEN + WAIT_FOR_LOCK)) 秒，父进程会硬停它；不存在它替你解锁这回事。"
echo "==> 10 秒后开始（要取消就现在 Ctrl-C）"
sleep 10

HARD=$((SECONDS_ON_SCREEN + WAIT_FOR_LOCK + 60))
LOG="$WORK/probe-$(date +%H%M%S).log"
echo "==> 日志：$LOG"
perl -e 'alarm shift; exec @ARGV' "$HARD" "$WORK/lock-probe" "$@" 2>&1 | tee "$LOG"
echo "==> 探针退出（父进程上限 ${HARD}s）。把 $LOG 发给我。"
