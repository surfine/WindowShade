#!/bin/bash
# 把一个功能场景摆好并撑住，再量这时 App 的空闲唤醒：看一眼探针的 --hold <kind>（见 tests/run-glance-probe.sh）
# 摆好场景后只睡 80 秒，这边在它就绪后调用 tools/perf/idle-wakeups.sh（等 36 秒、再采 30 秒）。
#
# 用法：
#   tools/perf/hold-and-measure.sh <kind> <label> [--out FILE]
#
# kind：pins、slide-over、carry、strip、split、pip、browser、shaded、none。
# 只在整机空闲 ≥ 120 秒时才跑（屏幕上会出现临时窗口，用户的键鼠会破坏场景）；
# 跑的时候持有 /private/tmp/ws-ui.lock（mkdir 锁，退出时释放），别的屏幕探针不要同时跑。
# 默认输出 .build/perf/hub-wakeups.jsonl（仓库里没有 docs/perf-data 约定）。需要先 `cd prototype && ./build.sh --stage`。

set -euo pipefail
cd "$(dirname "$0")/../.."

KIND="${1:-}"; LABEL="${2:-}"
[ -n "$KIND" ] && [ -n "$LABEL" ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift 2
OUT=".build/perf/hub-wakeups.jsonl"
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:?--out 需要路径}"; shift 2 ;;
    *) echo "未知选项：$1" >&2; exit 2 ;;
  esac
done
case "$KIND" in pins|slide-over|carry|strip|split|pip|browser|shaded|none) ;; *) echo "未知 kind：$KIND" >&2; exit 2 ;; esac
mkdir -p "$(dirname "$OUT")"

# awk 提前 exit 会让 ioreg 吃 SIGPIPE；pipefail 下整条管道就是 141、set -e 直接退出，所以读完全部输出。
IDLE="$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ && !seen {print int($NF/1e9); seen=1}')"
if [ "${IDLE:-0}" -lt 120 ]; then
  echo "拒绝：键鼠空闲只有 ${IDLE:-0} 秒（需要 ≥ 120）。等机器安静下来再跑。" >&2
  exit 1
fi

LOCK=/private/tmp/ws-ui.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  # 持有者已经不在了就接手，否则拒绝。
  HOLDER="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [ -n "$HOLDER" ] && kill -0 "$HOLDER" 2>/dev/null; then
    echo "拒绝：$LOCK 被进程 $HOLDER 持有。" >&2
    exit 1
  fi
  rm -rf "$LOCK"
  mkdir "$LOCK"
fi
echo $$ > "$LOCK/pid"

LOG="$(mktemp -t hold-probe)"
PROBE=""
cleanup() {
  if [ -n "$PROBE" ] && kill -0 "$PROBE" 2>/dev/null; then
    pkill -f glance-probe 2>/dev/null || true
    pkill -f GlanceFixture 2>/dev/null || true
  fi
  rm -f "$LOG"
  rm -rf "$LOCK"
}
trap cleanup EXIT

bash tests/run-glance-probe.sh --hold "$KIND" --hold-seconds 80 >"$LOG" 2>&1 &
PROBE=$!

# 就绪：包含编译临时 App 和起窗口，给 240 秒。
READY=""
for _ in $(seq 1 240); do
  READY="$(grep -m1 '^HOLD READY' "$LOG" || true)"
  [ -n "$READY" ] && break
  grep -q '^FAIL' "$LOG" && { echo "场景没摆好：" >&2; cat "$LOG" >&2; exit 1; }
  kill -0 "$PROBE" 2>/dev/null || { echo "探针提前退出：" >&2; cat "$LOG" >&2; exit 1; }
  sleep 1
done
[ -n "$READY" ] || { echo "超时：240 秒内没等到 HOLD READY" >&2; exit 1; }
echo "$READY"
APP_PID="$(sed -n 's/.* pid=\([0-9][0-9]*\).*/\1/p' <<<"$READY")"
[ -n "$APP_PID" ] || { echo "读不出进程号：$READY" >&2; exit 1; }

bash tools/perf/idle-wakeups.sh "$APP_PID" "$LABEL" --out "$OUT"

# 探针睡满 80 秒后收场；多等 60 秒。
for _ in $(seq 1 60); do
  kill -0 "$PROBE" 2>/dev/null || break
  sleep 1
done
if kill -0 "$PROBE" 2>/dev/null; then
  echo "超时：探针没有按时收场" >&2
  exit 1
fi
STATUS=0
wait "$PROBE" || STATUS=$?
grep -E '^(PASS|FAIL) hold' "$LOG" || true
exit "$STATUS"
