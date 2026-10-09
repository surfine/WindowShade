#!/bin/bash
# 空闲唤醒归因：量一个进程在“没人碰电脑”时的 CPU 与空闲唤醒次数。
#
# 用法：
#   tools/perf/idle-wakeups.sh <pid> [label] [--out FILE] [--build NUM] [--powermetrics]
#
# 流程：等 36 秒让界面安静下来，再用 top 连续采 30 秒（每秒一次），
# 取 %CPU 与 IDLEW 的均值，追加一行 JSON 到 --out 指定的文件（默认 ./idle-wakeups.jsonl）。
#
# --powermetrics：不自己提权，只打印需要 Aaron 手动用 sudo 执行的
# powermetrics 与 spindump 命令；脚本本身不 sudo。
#
# 测试用覆盖：IDLE_WAKEUPS_DELAY（默认 36）、IDLE_WAKEUPS_SAMPLES（默认 30）。

set -euo pipefail

DELAY="${IDLE_WAKEUPS_DELAY:-36}"
SAMPLES="${IDLE_WAKEUPS_SAMPLES:-30}"
OUT="idle-wakeups.jsonl"
BUILD=""
POWERMETRICS=0
PID=""
LABEL=""

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --out) OUT="${2:?--out 需要路径}"; shift 2 ;;
    --build) BUILD="${2:?--build 需要值}"; shift 2 ;;
    --powermetrics) POWERMETRICS=1; shift ;;
    --*) echo "未知选项：$1" >&2; usage 2 ;;
    *)
      if [ -z "$PID" ]; then PID="$1"
      elif [ -z "$LABEL" ]; then LABEL="$1"
      else echo "多余参数：$1" >&2; usage 2
      fi
      shift ;;
  esac
done

[ -n "$PID" ] || usage 2
case "$PID" in *[!0-9]*) echo "pid 必须是数字：$PID" >&2; exit 2 ;; esac
ps -p "$PID" >/dev/null 2>&1 || { echo "进程不存在：$PID" >&2; exit 1; }
LABEL="${LABEL:-unlabeled}"

if [ -z "$BUILD" ]; then
  # 从可执行文件往上找 .app，读 CFBundleVersion；找不到就记 unknown。
  EXE="$(ps -p "$PID" -o comm= 2>/dev/null | sed 's/^ *//')"
  APP="${EXE%%.app/*}.app"
  BUILD="unknown"
  if [ -n "$EXE" ] && [ -f "$APP/Contents/Info.plist" ]; then
    BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
  fi
fi

echo "等待 ${DELAY} 秒让空闲稳定（pid $PID，$LABEL）……"
sleep "$DELAY"

echo "采样 ${SAMPLES} 秒……"
TOP_OUT="$(top -l $((SAMPLES + 1)) -s 1 -stats pid,cpu,idlew -pid "$PID" 2>/dev/null || true)"

# top 的第一次采样是起算的，丢掉；其余每行格式为 "PID CPU IDLEW"。
read -r CPU IDLEW N <<EOF
$(printf '%s\n' "$TOP_OUT" | awk -v pid="$PID" '
  $1 == pid && NF >= 3 {
    n++
    if (n == 1) next
    cpu += $2; idle += $3; m++
  }
  END {
    if (m == 0) { print "NaN NaN 0"; exit }
    printf "%.3f %.3f %d\n", cpu / m, idle / m, m
  }')
EOF

if [ "$N" = "0" ]; then
  echo "没有采到数据：top 没有输出 pid $PID 的行" >&2
  exit 1
fi

TS="$(date '+%Y-%m-%dT%H:%M:%S%z')"
mkdir -p "$(dirname "$OUT")"
python3 -I -c '
import json, sys
label, ts, build, cpu, idlew, n, out = sys.argv[1:]
row = {
    "label": label,
    "time": ts,
    "build": build,
    "cpu": float(cpu),
    "idlew": float(idlew),
    "idlew_per_s": float(idlew),
    "samples": int(n),
}
with open(out, "a", encoding="utf-8") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")
print(json.dumps(row, ensure_ascii=False))
' "$LABEL" "$TS" "$BUILD" "$CPU" "$IDLEW" "$N" "$OUT"

echo "已追加到：$OUT"

if [ "$POWERMETRICS" = "1" ]; then
  SPIN="${OUT%.jsonl}-spindump-${PID}.txt"
  cat <<EOF

请 Aaron 手动执行（脚本不 sudo）：

  sudo powermetrics --samplers tasks --show-process-wakeups --show-process-energy -i 1000 -n 30 > powermetrics-${LABEL}.txt

  sudo spindump ${PID} 10 10 -file ${SPIN}

采样期间保持与上面相同的场景。跑完后把输出路径告诉我，再对照这一行 JSON。
EOF
fi
