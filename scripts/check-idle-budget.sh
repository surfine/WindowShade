#!/bin/bash
# 性能预算进门禁（规格 R44）：先只上最稳的一条——窗口浏览的程序坞悬停关着时，常驻系统查询为零。
# 用法：check-idle-budget.sh <WindowShade 可执行文件>
# 跑 --window-browser-idle-probe（临时关掉程序坞悬停、起控制器、等 1 秒、读计数、原样恢复设置），
# 两行读数里 AX 查询、在途缩略图、缩略图缓存都要是 0，且设置已恢复；否则非零退出。
set -euo pipefail
BIN="${1:?WindowShade executable}"
out=$(perl -e 'alarm 10; exec @ARGV' "$BIN" --window-browser-idle-probe 2>&1) || {
  echo "FAIL idle-budget: 探针没有在 10 秒内正常结束：${out:-无输出}" >&2; exit 1; }
first=$(printf '%s\n' "$out" | grep '^idle-probe: dockEnabled=false' || true)
after=$(printf '%s\n' "$out" | grep '^idle-probe: afterStop' || true)
want='axQueries=0 thumbnailsInFlight=0 thumbnailBytes=0'
if [[ "$first" == *"$want"* && "$after" == *"$want"* && "$after" == *"settingsRestored=true"* ]]; then
  echo "PASS idle-budget: 程序坞悬停关着时 AX 查询、在途缩略图、缓存都是 0，设置已恢复"
else
  echo "FAIL idle-budget: 预算是「全为 0 且设置恢复」，实际：" >&2
  printf '%s\n%s\n' "$first" "$after" >&2
  exit 1
fi
