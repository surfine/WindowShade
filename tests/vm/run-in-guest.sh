#!/bin/bash
# 在虚拟机里跑核心探针：每组一个进程，经 open 进图形会话；日志与收起记录放在 ~/wsqa-run 下。
cd "$HOME/wsqa-run" || exit 1
mkdir -p logs results && chmod 700 logs
for suite in "$@"; do
  log="$HOME/wsqa-run/logs/$suite.log"; : > "$log"; chmod 600 "$log"
  out="$HOME/wsqa-run/results/$suite.txt"; rm -f "$out"
  open -n -W --env WINDOWSHADE_LOG_PATH="$log" --env WINDOWSHADE_PROBE_ROOT="$HOME/wsqa-run" \
    --stdout "$out" --stderr "$out" ./WindowShade.app \
    --args --glance-probe --fixture "$HOME/wsqa-run/GlanceFixture.app/Contents/MacOS/GlanceFixture" "--$suite"
  fails=$(grep -c '^FAIL' "$out"); verdict=$(grep '^verdict' "$out")
  echo "== $suite fails=$fails $verdict"
  grep -E '^(FAIL|INFO (restore|glance)|TIMING|PASS fold-unmin)' "$out" | cut -c1-220
done
