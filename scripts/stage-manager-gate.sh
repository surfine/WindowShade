#!/bin/bash
# 台前调度真机门禁（发布流程第 2 步，FAIL 就挡发布）。
# 先 `cd prototype && ./build.sh --stage`，再跑这个脚本。它会短暂占用屏幕，只动临时 App 的窗口。
# 需要：台前调度开着、至少两块屏幕、副屏上至少两张桌面（调度中心里给外接屏加一张）。
# 缺任何一项会打印 SKIP 或 “skipped”，这里一律当失败：没跑到的边界不能算过关。
# 用法：bash scripts/stage-manager-gate.sh
set -uo pipefail
cd "$(dirname "$0")/.."
APP=${PROBE_APP:-.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade}
[ -x "$APP" ] || { echo "FAIL stage-manager-gate: 没有签名构建 $APP。先 cd prototype && ./build.sh --stage" >&2; exit 1; }

probes=(--fold-desktops --slide-over --slide-over-unminimizable --second-display --second-display-desktops --restore-guard)
fails=0
for flag in "${probes[@]}"; do
  echo "=== stage-manager-gate $flag"
  out=$(mktemp -t stage-gate)
  bash tests/run-glance-probe.sh "$flag" >"$out" 2>&1 || true
  cat "$out"
  # 整项没跑（缺屏幕、缺桌面、台前调度关着）也算没过。不能拿子步骤里正常的
  # “skipped”（例如侧拉在台前调度下本来就不走离屏恢复）去挡。
  if grep -qE '^FAIL|^SKIP' "$out" || grep -qE '^INFO .*(only one desktop|Stage Manager is off|desktops could not be read).*skipped' "$out"; then
    echo "FAIL stage-manager-gate: $flag 没过（有 FAIL、SKIP，或因为缺屏幕／桌面／台前调度被跳过）"
    fails=$((fails + 1))
  else
    echo "PASS stage-manager-gate: $flag"
  fi
  rm -f "$out"
done
if [ "$fails" -ne 0 ]; then
  echo "FAIL stage-manager-gate: $fails 项没过，不能发布"
  exit 1
fi
echo "PASS stage-manager-gate: 六项都过了"
