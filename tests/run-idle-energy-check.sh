#!/bin/bash
# 空闲能耗采样（2026-10-31 决定 #50 f）：对一份正在运行的隔离构建，每 5 秒采一次 CPU，持续 N 分钟，
# 打印一行汇总（平均、最大 CPU%、线程数范围、唤醒数），再和门槛比较。不启动、不退出 App，只读 `ps`／`top`。
# 先 `cd prototype && ./build.sh --stage`，启动它，放着别碰（屏幕可以亮着，别操作）。
# 门槛：docs/perf-energy.md（内部仓库）没有给“空闲应低于多少”的硬数字，只有同类实测——
# 盒盖效果关着约 0.31%、开着约 0.45%（60 秒静置）。这里取 1.0% 作平均 CPU 的默认门槛，WS_IDLE_CPU_MAX 可改；
# 唤醒数没有文档门槛，只报告，除非设了 WS_IDLE_WAKEUPS_MAX（每秒）。
# 用法：tests/run-idle-energy-check.sh [分钟数，默认 3]
set -euo pipefail
MINUTES=${1:-3}
CPU_MAX=${WS_IDLE_CPU_MAX:-1.0}
WAKEUPS_MAX=${WS_IDLE_WAKEUPS_MAX:-}
case "$MINUTES" in ''|*[!0-9]*) echo "minutes must be a positive integer" >&2; exit 2 ;; esac
[ "$MINUTES" -ge 1 ] || { echo "minutes must be at least 1" >&2; exit 2; }
pids=$(pgrep -x WindowShade || true)
if [ -z "$pids" ]; then
  echo "SKIP idle-energy: WindowShade is not running (start the staged app first: .build/duo-validation/WindowShade.app)"
  exit 0
fi
if [ "$(echo "$pids" | wc -l | tr -d ' ')" -gt 1 ]; then
  echo "FAIL idle-energy: more than one WindowShade is running ($(echo "$pids" | tr '\n' ' ')); quit the others so the numbers are about one app" >&2
  exit 2
fi
pid=$pids
idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
echo "INFO idle-energy: pid=$pid minutes=$MINUTES threshold_cpu=${CPU_MAX}% (idle seconds since last input: ${idle:-unknown}; stay off the keyboard and trackpad)"

samples=$((MINUTES * 12))
cpu_file=$(mktemp)
trap 'rm -f "$cpu_file"' EXIT
# top -l 2 的第二帧才是区间值（第一帧是自启动累计）；-stats 取 pid,cpu,th,idlew（空闲唤醒），-s 5 每 5 秒一帧。
top -l $((samples + 1)) -s 5 -pid "$pid" -stats pid,cpu,th,idlew 2>/dev/null |
  awk -v pid="$pid" '$1 == pid {n++; if (n > 1) print $2, $3, $4}' > "$cpu_file" || true
count=$(wc -l < "$cpu_file" | tr -d ' ')
if [ "$count" -lt 1 ]; then
  echo "FAIL idle-energy: no samples collected (did the app quit while sampling?)" >&2
  exit 1
fi
# idlew 是累计到当前帧的“空闲唤醒”次数：用最后一帧减第一帧得到区间内总数。
summary=$(awk -v minutes="$MINUTES" '
  { cpu += $1; if ($1 > max) max = $1; if (NR == 1 || $2 < tmin) tmin = $2; if ($2 > tmax) tmax = $2
    gsub(/[^0-9]/, "", $3); if (NR == 1) w0 = $3; w1 = $3 }
  END { printf "samples=%d cpu_avg=%.2f%% cpu_max=%.1f%% threads=%d-%d wakeups_total=%d wakeups_per_s=%.1f", NR, cpu / NR, max, tmin, tmax, w1 - w0, (w1 - w0) / (minutes * 60) }' "$cpu_file")
echo "SUMMARY idle-energy: $summary"
avg=$(awk '{ cpu += $1 } END { printf "%.4f", cpu / NR }' "$cpu_file")
verdict=PASS
if awk -v a="$avg" -v m="$CPU_MAX" 'BEGIN { exit !(a > m) }'; then
  echo "FAIL idle-energy: average CPU ${avg}% is above the ${CPU_MAX}% threshold"
  verdict=FAIL
fi
if [ -n "$WAKEUPS_MAX" ]; then
  per_s=$(echo "$summary" | sed -n 's/.*wakeups_per_s=\([0-9.]*\).*/\1/p')
  if awk -v a="$per_s" -v m="$WAKEUPS_MAX" 'BEGIN { exit !(a > m) }'; then
    echo "FAIL idle-energy: ${per_s} wakeups/s is above the ${WAKEUPS_MAX}/s threshold"
    verdict=FAIL
  fi
fi
if [ "${idle:-0}" -lt $((MINUTES * 60)) ] 2>/dev/null; then
  echo "INFO idle-energy: there was input during the run, so the numbers may include your own activity"
fi
echo "$verdict idle-energy: $summary"
[ "$verdict" = PASS ]
