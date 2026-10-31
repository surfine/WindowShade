#!/bin/bash
# 系统更新之后该重跑哪些探针（2026-10-31 决定 #52）：把 `sw_vers -productVersion` 记进 .build/last-probed-macos.txt，
# 和上次比；变了就打印要重跑的核心探针组（与 tests/vm/run-core-probes.sh 的默认组、真机常用组一致），
# 没变就只说没变。只打印、不自动做任何界面动作；重跑的命令由人决定。
# 每次运行都会把当前版本写进记录文件（所以只会在升级后的第一次提示）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
state=.build/last-probed-macos.txt
current=$(sw_vers -productVersion)
build=$(sw_vers -buildVersion)
previous=""
[ -f "$state" ] && previous=$(head -n 1 "$state")
# 核心组：取 tests/vm/run-core-probes.sh 里的默认组，读不到时用写死的同一份。
suites=$(sed -n 's/^\[ \${#suites\[@\]} -gt 0 \] || suites=(\(.*\))$/\1/p' tests/vm/run-core-probes.sh 2>/dev/null || true)
[ -n "$suites" ] || suites="fold-timing restore-guard fold-unminimizable orphan wins browser-more"
printf '%s\n' "$current" > "$state"
if [ "$previous" = "$current" ]; then
  echo "macOS $current ($build): unchanged since the last probe run; nothing to rerun"
  exit 0
fi
echo "macOS changed: ${previous:-none recorded} -> $current ($build)"
echo "Rerun these core probe suites on this Mac (signed staged build; cd prototype && ./build.sh --stage first):"
for suite in $suites; do
  echo "  tests/run-glance-probe.sh --$suite"
done
echo "Also worth a rerun after a system update: --dock-scenarios --gesture --close-quit --second-display --display-hotplug --overlay-input"
echo "In the QA virtual machines: tests/vm/run-core-probes.sh lume@<vm-address> $suites"
echo "(recorded macOS $current in $state; this prompt only appears once per system update)"
