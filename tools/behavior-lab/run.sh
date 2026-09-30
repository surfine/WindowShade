#!/bin/bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"
TASK_ROOT="$(cd "$TASK_DIR/../.." && pwd)"
mkdir -p "$TASK_ROOT/.build/behavior-lab"
swiftc -O -target "$(uname -m)-apple-macosx14.0" -framework Foundation -framework CoreGraphics -framework Carbon \
  "$TASK_DIR/TimingFeatures.swift" "$TASK_DIR/BehaviorRisk.swift" "$TASK_DIR/main.swift" \
  -o "$TASK_ROOT/.build/behavior-lab/BehaviorLab"
exec "$TASK_ROOT/.build/behavior-lab/BehaviorLab" "$@"
