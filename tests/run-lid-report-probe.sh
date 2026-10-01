#!/bin/bash
# 盖角设备会不会主动推送角度变化？（独立可执行，不进 App；锁屏也能跑，但要有结论就得有人在旁边合盖）
#   bash tests/run-lid-report-probe.sh               默认 15 秒
#   bash tests/run-lid-report-probe.sh --seconds 30
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=.build/lid-report-probe
mkdir -p "$WORK"
swiftc -O -parse-as-library tools/lid-report-probe/LidReportProbe.swift -o "$WORK/lid-report-probe"
exec "$WORK/lid-report-probe" "$@"
