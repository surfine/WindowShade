#!/bin/bash
# 本地门禁：替代托管 CI 的可重复验证入口。
#
# 用法：
#   scripts/local-gate.sh check                 # build.sh --check（约 5 分钟）
#   scripts/local-gate.sh unit [--jobs 4]       # 跑全部单元脚本，排除表见 tests/gate-excludes.tsv
#   scripts/local-gate.sh appkit                # tests/run-appkit-tests.sh all
#   scripts/local-gate.sh vm --host lume@<地址> # 虚拟机核心探针
#   scripts/local-gate.sh release --previous <上一版 zip> [--previous-intel <上一版 -intel.zip>]
#                                               # x86_64 的 --check、两个架构的 --release 构建，再对 arm64 和 -intel 两个 zip 各过一遍发布关
#   scripts/local-gate.sh all                   # check + unit + appkit
#   scripts/local-gate.sh list                  # 只列出 unit 会跑什么、排除了什么
#
# 结果写到 .build/gate/<UTC>-<sha>-<profile>/：
#   summary.json  机器可读（提交、脏工作区、工具链、逐项耗时与退出码）
#   logs/         每项完整输出 + .status
#
# 退出码：0 全过；1 有失败；2 参数错；3 环境不满足。
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

profile="${1:-check}"
shift || true

jobs=4
test_timeout=300
only=""
host=""
previous=""
previous_intel=""
list_only=0

while [ $# -gt 0 ]; do
  case "$1" in
    --jobs) jobs="$2"; shift 2 ;;
    --timeout) test_timeout="$2"; shift 2 ;;
    --only) only="$2"; shift 2 ;;
    --host) host="$2"; shift 2 ;;
    --previous) previous="$2"; shift 2 ;;
    --previous-intel) previous_intel="$2"; shift 2 ;;
    --list) list_only=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

case "$profile" in
  check|unit|appkit|vm|release|all|list) ;;
  *) echo "未知 profile：${profile}（见 --help）" >&2; exit 2 ;;
esac

sha="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dir=".build/gate/${stamp}-${sha}-${profile}"
mkdir -p "$dir/logs"
results="$dir/results.tsv"
: >"$results"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
started_epoch=$(date +%s)

failures=0

say() { printf '%s\n' "$*"; }

record() { # name rc seconds log
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$results"
  if [ "$2" -ne 0 ]; then
    failures=$((failures + 1))
    say "FAIL  $1  exit=$2  ${3}s  ($4)"
  else
    say "ok    $1  ${3}s"
  fi
}

run_item() { # name timeout command…
  local name="$1" timeout_s="$2"
  shift 2
  local log="$dir/logs/$name.log" status="$dir/logs/$name.status"
  scripts/gate-run-one.sh "$timeout_s" "$log" "$status" "$@"
  local rc secs
  read -r rc secs <"$status"
  record "$name" "$rc" "$secs" "$log"
}

preflight() {
  local missing=0
  for tool in git bash xcrun xcodebuild python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      say "缺少工具：$tool"
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then exit 3; fi
  if ! command -v rg >/dev/null 2>&1; then
    say "提示：没有 ripgrep（rg），AppKit 套件会跳过部分测试"
  fi
  if [ ! -f prototype/Vendor/Sparkle.framework/Versions/B/Sparkle ]; then
    say "缺少 prototype/Vendor/Sparkle.framework，--check 会失败"
    exit 3
  fi
  if [ -d ../WindowShade-models/speaker/SpeakerEmbedding.mlpackage ]; then
    say "声纹模型：在，构建会包含 SpeakerEmbedding"
  else
    say "声纹模型：不在（../WindowShade-models/speaker），本次构建不含 SpeakerEmbedding"
  fi
}

excluded_reason() { # 脚本名 → 命中排除表时打印原因
  awk -F'\t' -v n="$1" '
    $0 ~ /^[[:space:]]*#/ { next }
    NF >= 2 && $1 == n { print $2; exit }
  ' tests/gate-excludes.tsv 2>/dev/null
}

discover_unit() { # 输出到 $dir/unit-list.txt，被排除的写到 unit-excluded.txt
  : >"$dir/unit-list.txt"
  : >"$dir/unit-excluded.txt"
  local f base reason
  for f in tests/run-*.sh; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    reason="$(excluded_reason "$base")"
    if [ -n "$reason" ]; then
      printf '%s\t%s\n' "$base" "$reason" >>"$dir/unit-excluded.txt"
      continue
    fi
    if [ -n "$only" ]; then
      case "$base" in
        *"$only"*) ;;
        *) continue ;;
      esac
    fi
    printf '%s\n' "$f" >>"$dir/unit-list.txt"
  done
}

run_units() {
  discover_unit
  local total parallel serial
  total="$(wc -l <"$dir/unit-list.txt" | tr -d ' ')"
  if [ "$total" -eq 0 ]; then
    say "没有要跑的单元脚本"
    return
  fi
  : >"$dir/unit-parallel.txt"
  : >"$dir/unit-serial.txt"
  local script base
  while IFS= read -r script; do
    base="$(basename "$script")"
    if grep -qxF "$base" tests/gate-serial.txt 2>/dev/null; then
      printf '%s\n' "$script" >>"$dir/unit-serial.txt"
    else
      printf '%s\n' "$script" >>"$dir/unit-parallel.txt"
    fi
  done <"$dir/unit-list.txt"
  parallel="$(wc -l <"$dir/unit-parallel.txt" | tr -d ' ')"
  serial="$(wc -l <"$dir/unit-serial.txt" | tr -d ' ')"
  say "单元脚本：${total} 个（并行 ${parallel}，串行 ${serial}），排除 $(wc -l <"$dir/unit-excluded.txt" | tr -d ' ')，并行 ${jobs}"

  if [ "$parallel" -gt 0 ]; then
    xargs -I{} -P "$jobs" bash -c '
      script="$1"; dir="$2"; root="$3"; timeout_s="$4"
      name=$(basename "$script" .sh)
      "$root/scripts/gate-run-one.sh" "$timeout_s" \
        "$dir/logs/$name.log" "$dir/logs/$name.status" bash "$script" </dev/null
    ' _ {} "$dir" "$ROOT" "$test_timeout" <"$dir/unit-parallel.txt"

    local st name rc secs
    while IFS= read -r script; do
      name="$(basename "$script" .sh)"
      st="$dir/logs/$name.status"
      [ -f "$st" ] || continue
      read -r rc secs <"$st"
      record "$name" "$rc" "$secs" "$dir/logs/$name.log"
    done <"$dir/unit-parallel.txt"
  fi

  # 共用 .build/native 的脚本必须串行，否则会互相覆盖 WS2Child.o。
  if [ "$serial" -gt 0 ]; then
    while IFS= read -r script; do
      base="$(basename "$script" .sh)"
      run_item "$base" 900 bash "$script"
    done <"$dir/unit-serial.txt"
  fi
}

write_summary() {
  local ended_at ended_epoch
  ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ended_epoch=$(date +%s)
  PROFILE="$profile" SHA="$sha" DIRTY="$dirty" BRANCH="$branch" \
  STARTED="$started_at" ENDED="$ended_at" \
  ELAPSED="$((ended_epoch - started_epoch))" DIR="$dir" RESULTS="$results" \
  python3 - <<'PY'
import json, os, platform, subprocess

def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15).stdout.strip()
    except Exception:
        return ""

items = []
path = os.environ["RESULTS"]
if os.path.exists(path):
    with open(path) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 4:
                continue
            items.append({"name": parts[0], "exit": int(parts[1]),
                          "seconds": int(parts[2]), "log": parts[3]})

summary = {
    "profile": os.environ["PROFILE"],
    "commit": os.environ["SHA"],
    "branch": os.environ["BRANCH"],
    "dirty_files": int(os.environ["DIRTY"]),
    "started_at": os.environ["STARTED"],
    "ended_at": os.environ["ENDED"],
    "elapsed_seconds": int(os.environ["ELAPSED"]),
    "macos": sh("sw_vers -productVersion") + " " + sh("sw_vers -buildVersion"),
    "architecture": platform.machine(),
    "xcode": sh("xcodebuild -version | tr '\\n' ' '"),
    "swift": sh("swift --version | head -1"),
    "sdk": sh("xcrun --show-sdk-version --sdk macosx"),
    "speaker_model": os.path.isdir("../WindowShade-models/speaker/SpeakerEmbedding.mlpackage"),
    "items": items,
    "failures": [i for i in items if i["exit"] != 0],
}
with open(os.path.join(os.environ["DIR"], "summary.json"), "w") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)
print("证据：" + os.path.join(os.environ["DIR"], "summary.json"))
PY
}

preflight

case "$profile" in
  list)
    discover_unit
    say "会跑："
    sed 's/^/  /' "$dir/unit-list.txt"
    say "排除："
    sed 's/^/  /' "$dir/unit-excluded.txt"
    rm -rf "$dir"
    exit 0
    ;;
  check)
    run_item build-check 1800 bash -c 'cd prototype && ./build.sh --check'
    ;;
  unit)
    run_units
    ;;
  appkit)
    run_item appkit-all 1800 bash tests/run-appkit-tests.sh all
    ;;
  vm)
    if [ -z "$host" ]; then say "需要 --host lume@<地址>"; exit 2; fi
    run_item vm-core-probes 3600 tests/vm/run-core-probes.sh "$host"
    ;;
  release)
    if [ -z "$previous" ]; then say "需要 --previous <上一版 zip>（离线发布关）"; exit 2; fi
    if [ "$dirty" -ne 0 ]; then say "工作区不干净（$dirty 个文件），发布关拒绝继续"; exit 1; fi
    run_item check-release-version 120 bash scripts/check-release-version.sh
    version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' prototype/Info.plist)"
    # Intel 实验版（从 1.0.21 起另发一个 zip）：先过 x86_64 的编译链接检查，再各自出 Developer ID 包。
    run_item build-check-x86_64 1800 bash -c 'cd prototype && WINDOWSHADE_ARCH=x86_64 ./build.sh --check'
    run_item build-release 3600 bash -c 'cd prototype && ./build.sh --release'
    run_item build-release-intel 3600 bash -c 'cd prototype && WINDOWSHADE_ARCH=x86_64 ./build.sh --release'
    # zip 由 docs/DEVELOPMENT.md 发布流程第 3 步从两个产物各打一个（公证之后）；这里只核它们。
    run_item release-gate 600 bash scripts/release-gate.sh --previous "$previous" \
      "prototype/dist/WindowShade-v${version}.zip"
    run_item release-gate-intel 600 bash scripts/release-gate.sh --previous "${previous_intel:-$previous}" \
      "prototype/dist/WindowShade-v${version}-intel.zip"
    ;;
  all)
    run_item build-check 1800 bash -c 'cd prototype && ./build.sh --check'
    run_units
    run_item appkit-all 1800 bash tests/run-appkit-tests.sh all
    ;;
esac

write_summary
if [ "$failures" -ne 0 ]; then
  say "失败 $failures 项"
  exit 1
fi
say "全部通过"
