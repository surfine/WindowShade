#!/bin/bash
# 录一段真实盖角序列：bash tools/lid-trace/record.sh <名字> [秒数，默认 20]
set -euo pipefail
cd "$(dirname "$0")/../.."
name=${1:?需要一个名字，例如 slow-close}
seconds=${2:-20}
mkdir -p .build/lid-trace tests/fixtures/lid-traces
swiftc -O -parse-as-library tools/lid-trace/LidTraceRecorder.swift -o .build/lid-trace/recorder
exec .build/lid-trace/recorder "tests/fixtures/lid-traces/$name.csv" "$seconds"
