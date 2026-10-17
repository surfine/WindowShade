#!/bin/bash
# 卡顿账（1.0.18 计划第 5 条）：跑 --hitch，把 HITCH 行落盘成 JSON，并在 docs/perf-ledger.md 记一行。只报不挡：
# 量到的数字对照 Apple 卡顿预算（真机 ratio < 5 ms/s 且 worst < 100 ms；虚拟机只看 worst < 500 ms），
# 不过线也退出 0。只有「没跑出任何 HITCH 行」才非零，那是探针没跑成，不是卡顿。
# 不接进 prototype/build.sh（它会在 CI／主机构建里跑，不能带界面探针）。
#
# 用法：
#   scripts/perf-report.sh --host [--rounds N] [--force]      本机：先 cd prototype && ./build.sh --stage；
#                                                              需要本机已闲置 ≥ 20 秒（HIDIdleTime），--force 跳过这项检查；
#                                                              探针会在屏幕上短暂开一扇临时窗口，不碰你的窗口，也不动真鼠标
#   scripts/perf-report.sh --vm lume@<ip> [--rounds N]        虚拟机：走 tests/vm/run-core-probes.sh（先在本机跑过一次 tests/run-glance-probe.sh）
#   scripts/perf-report.sh --parse <日志文件> [--machine 文字]  只解析已有输出（包含 HITCH 行），不跑探针；用于补记和自测
#   --no-ledger   只写 .build/perf/*.json，不改 docs/perf-ledger.md
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=""; VMHOST=""; ROUNDS=20; FORCE=0; LOGFILE=""; MACHINE_OVERRIDE=""; LEDGER=1
while [ $# -gt 0 ]; do
  case "$1" in
    --host) MODE=host; shift ;;
    --vm) MODE=vm; VMHOST="${2:?--vm needs lume@<ip>}"; shift 2 ;;
    --parse) MODE=parse; LOGFILE="${2:?--parse needs a file}"; shift 2 ;;
    --rounds) ROUNDS="${2:?}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --machine) MACHINE_OVERRIDE="${2:?}"; shift 2 ;;
    --no-ledger) LEDGER=0; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { echo "usage: perf-report.sh --host | --vm lume@<ip> | --parse <log>  [--rounds N] [--force] [--no-ledger]" >&2; exit 2; }
[[ "$ROUNDS" =~ ^[0-9]+$ ]] || { echo "--rounds 要是整数" >&2; exit 2; }

APP=.build/duo-validation/WindowShade.app
plist() { [ -f "$APP/Contents/Info.plist" ] && /usr/libexec/PlistBuddy -c "Print $1" "$APP/Contents/Info.plist" 2>/dev/null || true; }
BUILD=$(plist CFBundleVersion); VERSION=$(plist CFBundleShortVersionString)
COMMIT=$(git rev-parse --short=9 HEAD 2>/dev/null || echo unknown)
DIRTY=""; git diff --quiet HEAD -- 2>/dev/null || DIRTY="+dirty"
STAMP=$(date +%Y-%m-%d); TS=$(date +%Y%m%d-%H%M%S)
mkdir -p .build/perf
out=$(mktemp -t perf-report); trap 'rm -f "$out"' EXIT
RUN_STATUS=0

case "$MODE" in
  host)
    [ -d "$APP" ] || { echo "先 cd prototype && ./build.sh --stage（找不到 $APP）" >&2; exit 1; }
    if [ "$FORCE" != 1 ]; then
      idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1e9); exit}')
      [ "${idle:-0}" -ge 20 ] || { echo "本机不闲置（${idle:-?} 秒内有输入）：卡顿数字会被你的操作污染。等 20 秒不动，或加 --force" >&2; exit 3; }
    fi
    MACHINE="$(sysctl -n hw.model) · $(sysctl -n machdep.cpu.brand_string) · macOS $(sw_vers -productVersion)"
    bash tests/run-glance-probe.sh --hitch --hitch-rounds "$ROUNDS" 2>&1 | tee "$out" || RUN_STATUS=$?
    ;;
  vm)
    MACHINE="VM $VMHOST"
    WSQA_HITCH_ROUNDS="$ROUNDS" bash tests/vm/run-core-probes.sh "$VMHOST" hitch 2>&1 | tee "$out" || RUN_STATUS=$?
    g=$(grep -m1 '^guest macOS' "$out" || true); [ -z "$g" ] || MACHINE="VM · $g"
    ;;
  parse)
    [ -f "$LOGFILE" ] || { echo "找不到 $LOGFILE" >&2; exit 1; }
    cp "$LOGFILE" "$out"; MACHINE="unspecified"
    ;;
esac
[ -z "$MACHINE_OVERRIDE" ] || MACHINE="$MACHINE_OVERRIDE"

JSON=".build/perf/$TS-${BUILD:-nobuild}.json"
python3 -I - "$out" "$JSON" "$LEDGER" "${VERSION:-?}" "${BUILD:-?}" "$COMMIT$DIRTY" "$MACHINE" "$MODE" "$STAMP" "$RUN_STATUS" <<'PY'
import json, re, sys
log, jpath, ledger, version, build, commit, machine, mode, stamp, status = sys.argv[1:]
pat = re.compile(r'^HITCH (\S+) n=(\d+) ratio=([\d.]+) ms/s worst=([\d.]+) ms p95=([\d.]+) ms refresh=([\d.]+) Hz frames=(\d+) duration=([\d.]+) s tier=(\w+)')
text = open(log, errors='replace').read()
rows = []
for line in text.splitlines():
    m = pat.match(line.strip())
    if m:
        k, n, ratio, worst, p95, hz, frames, dur, tier = m.groups()
        rows.append({"kind": k, "n": int(n), "ratio_ms_per_s": float(ratio), "worst_ms": float(worst),
                     "p95_ms": float(p95), "refresh_hz": float(hz), "frames": int(frames),
                     "duration_s": float(dur), "tier": tier})
if not rows:
    print("perf-report: 没有解析到任何 HITCH 行（探针没跑成，或窗口浏览／看一眼都被设置关着）", file=sys.stderr)
    sys.exit(4)
vm = mode == "vm" or machine.startswith("VM") or re.search(r'virtual machine', text) is not None
# 对照 Apple 预算（只报不挡）。真机 ratio < 5 且 worst < 100；虚拟机只看 worst < 500，ratio 仅参考。
def verdict(r):
    if vm:
        return "within" if r["worst_ms"] < 500 else "over"
    return "within" if (r["ratio_ms_per_s"] < 5 and r["worst_ms"] < 100) else "over"
for r in rows:
    r["vs_budget"] = verdict(r)
over = [r["kind"] for r in rows if r["vs_budget"] == "over"]
skipped = re.findall(r'^SKIP hitch (\w+)', text, re.M)
doc = {"date": stamp, "version": version, "build": build, "commit": commit, "machine": machine,
       "kind_of_machine": "vm" if vm else "hardware",
       "budget": "worst<500ms (ratio info only)" if vm else "ratio<5ms/s and worst<100ms",
       "probe_exit_status": int(status), "skipped": skipped, "kinds": rows,
       "summary": "all kinds within budget" if not over else "over budget: " + ", ".join(over)}
json.dump(doc, open(jpath, "w"), indent=1, ensure_ascii=False); open(jpath, "a").write("\n")
print("perf-report: wrote " + jpath)
if ledger == "1":
    path = "docs/perf-ledger.md"
    detail = "; ".join("%s %.1f/%.0f" % (r["kind"], r["ratio_ms_per_s"], r["worst_ms"]) for r in rows)
    res = ("全部在预算内" if not over else "超预算：" + "、".join(over)) + ("（虚拟机仅 worst 判）" if vm else "")
    if skipped: res += "；跳过：" + "、".join(skipped)
    hz = "/".join(sorted({"%.0f" % r["refresh_hz"] for r in rows}))
    row = "| %s | %s (build %s) %s | %s | %s Hz | %s | %s |" % (stamp, version, build, commit, machine.replace("|", "/"), hz, res, detail)
    try:
        body = open(path).read()
    except FileNotFoundError:
        body = None
    if body is None:
        sys.exit("perf-report: docs/perf-ledger.md 不存在")
    if not body.endswith("\n"): body += "\n"
    open(path, "w").write(body + row + "\n")
    print("perf-report: appended a row to " + path)
for r in rows:
    print("  %-14s n=%-3d ratio=%6.2f ms/s worst=%7.1f ms p95=%6.1f ms %s" % (r["kind"], r["n"], r["ratio_ms_per_s"], r["worst_ms"], r["p95_ms"], r["vs_budget"]))
print("perf-report: " + doc["summary"] + "（只报不挡）")
PY
