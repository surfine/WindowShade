#!/bin/bash
# 空闲唤醒归因：量一个进程在“没人碰电脑”时的 CPU 与空闲唤醒次数。
#
# 用法：
#   tools/perf/idle-wakeups.sh <pid> [label] [--out FILE] [--build NUM] [--powermetrics]
#
# 流程：等 36 秒让界面安静下来，再按 proc_pid_rusage / proc_pidinfo 前后差采 30 秒，
# 取 %CPU 均值与 rusage 唤醒差（每秒），追加一行 JSON 到 --out 指定的文件（默认 ./idle-wakeups.jsonl）。
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

echo "等待 ${DELAY} 秒让空闲稳定（pid ${PID}，${LABEL}）……"
sleep "$DELAY"

# 唤醒次数取 proc_pid_rusage 的前后差（ri_pkg_idle_wkups、ri_interrupt_wkups）：
# 2026-11-05 在 macOS 27 上实测，top -pid 的 IDLEW 列是进程累计值、30 秒内纹丝不动，不能当每秒次数用。
rusage_wakeups() {
  python3 -I -c '
import ctypes, sys, time
class RU(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16), ("user", ctypes.c_uint64), ("system", ctypes.c_uint64),
                ("pkg_idle", ctypes.c_uint64), ("interrupt", ctypes.c_uint64), ("rest", ctypes.c_uint64 * 40)]
r = RU()
if ctypes.CDLL("/usr/lib/libproc.dylib").proc_pid_rusage(int(sys.argv[1]), 4, ctypes.byref(r)) != 0:
    sys.exit(1)
# 上下文切换（proc_pidinfo PROC_PIDTASKINFO 的 pti_csw）与 CPU 时间：机器忙时 CPU 很少真空闲，
# interrupt 唤醒会被压低、波动大，这两项不受别的进程负载影响，前后对比以它们为准。
class TI(ctypes.Structure):
    _fields_ = [("vsize", ctypes.c_uint64), ("rsize", ctypes.c_uint64), ("user", ctypes.c_uint64), ("system", ctypes.c_uint64),
                ("tuser", ctypes.c_uint64), ("tsystem", ctypes.c_uint64), ("policy", ctypes.c_int32), ("faults", ctypes.c_int32),
                ("pageins", ctypes.c_int32), ("cow", ctypes.c_int32), ("msgs", ctypes.c_int32), ("msgr", ctypes.c_int32),
                ("mach", ctypes.c_int32), ("unix", ctypes.c_int32), ("csw", ctypes.c_int32), ("threads", ctypes.c_int32),
                ("running", ctypes.c_int32), ("priority", ctypes.c_int32)]
t = TI()
if ctypes.CDLL("/usr/lib/libproc.dylib").proc_pidinfo(int(sys.argv[1]), 4, ctypes.c_uint64(0), ctypes.byref(t), ctypes.sizeof(t)) != ctypes.sizeof(t):
    sys.exit(1)
class TB(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]
tb = TB(); ctypes.CDLL("/usr/lib/libSystem.dylib").mach_timebase_info(ctypes.byref(tb))
# ri_user_time / ri_system_time 是 mach 时基单位（Apple 芯片上 1 单位 ≈ 41.7 ns），换成纳秒。
print(r.pkg_idle, r.interrupt, time.time(), t.csw, (r.user + r.system) * tb.numer // tb.denom)
' "$PID"
}

echo "采样 ${SAMPLES} 秒……"
read -r IDLE0 INTR0 T0 CSW0 CPUNS0 <<<"$(rusage_wakeups)" || { echo "读不到 pid $PID 的 rusage" >&2; exit 1; }
[ -n "${CSW0:-}" ] || { echo "读不到 pid $PID 的 rusage" >&2; exit 1; }
# 采样窗口由 sleep 定死。原来用 top -l N -s 1 计时兼取 CPU%：机器忙时它会拖到 N 秒的三倍
# （11-06 实测 31 次采样花了 97 秒），量到场景结束之后。CPU% 改由同一对 rusage 的 CPU 时间算。
sleep "$SAMPLES"
read -r IDLE1 INTR1 T1 CSW1 CPUNS1 <<<"$(rusage_wakeups)" || { echo "读不到 pid $PID 的 rusage" >&2; exit 1; }
[ -n "${CSW1:-}" ] || { echo "读不到 pid $PID 的 rusage（进程已退出？）" >&2; exit 1; }

read -r IDLEW INTRW CSWS CPUMS <<<"$(awk -v a="$IDLE0" -v b="$IDLE1" -v c="$INTR0" -v d="$INTR1" -v s="$T0" -v e="$T1" \
  -v w0="$CSW0" -v w1="$CSW1" -v n0="$CPUNS0" -v n1="$CPUNS1" \
  'BEGIN { dt = e - s; printf "%.3f %.3f %.2f %.4f\n", (b - a) / dt, (d - c) / dt, (w1 - w0) / dt, (n1 - n0) / dt / 1e6 }')"

# CPU%：采样窗口内 CPU 时间 / 墙钟时间。
CPU="$(awk -v ms="$CPUMS" 'BEGIN { printf "%.3f", ms / 10 }')"
N="$SAMPLES"

TS="$(date '+%Y-%m-%dT%H:%M:%S%z')"
mkdir -p "$(dirname "$OUT")"
python3 -I -c '
import json, sys
label, ts, build, cpu, idlew, intrw, csw, cpums, n, out = sys.argv[1:]
row = {
    "label": label,
    "time": ts,
    "build": build,
    "cpu": float(cpu),
    "idlew_per_s": float(idlew),
    "interrupt_wakeups_per_s": float(intrw),
    "csw_per_s": float(csw),
    "cpu_ms_per_s": float(cpums),
    "samples": int(n),
}
with open(out, "a", encoding="utf-8") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")
print(json.dumps(row, ensure_ascii=False))
' "$LABEL" "$TS" "$BUILD" "$CPU" "$IDLEW" "$INTRW" "$CSWS" "$CPUMS" "$N" "$OUT"

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
