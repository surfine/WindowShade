#!/bin/zsh
set -eu
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUO_BIN="$TASK_ROOT/.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade"
if [[ ! -x "$DUO_BIN" ]]; then
  print '请先运行 prototype/build.sh --stage 构建试用版。'
  exit 1
fi
cd "$TASK_ROOT"
exec "$DUO_BIN" --duo-desktop-demo
