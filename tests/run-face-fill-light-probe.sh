#!/usr/bin/env bash
# 认你指示的页面级验收：真 App 里依次放取景、收集、结束三个相位，检查卡片尺寸/提示/进度/收走。
# 没有相机、没有 Touch ID、没有模型请求。需要开发签名证书。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/prototype"
# 签名身份：先看环境变量，再读 prototype/local-codesign.env（不入 Git），规则和 build.sh 相同。
if [ -z "${WINDOWSHADE_CODESIGN_IDENTITY:-}" ] && [ -f local-codesign.env ]; then
  # shellcheck disable=SC1091
  source local-codesign.env
fi
if [ -z "${WINDOWSHADE_CODESIGN_IDENTITY:-}" ]; then
  echo "ERROR: 未提供签名身份。请设置 WINDOWSHADE_CODESIGN_IDENTITY，或创建 prototype/local-codesign.env（不提交进 Git）。" >&2
  exit 1
fi
export WINDOWSHADE_CODESIGN_IDENTITY
./build.sh --stage
APP="$ROOT/.build/duo-validation/WindowShade.app"
if pgrep -x WindowShade >/dev/null 2>&1; then
  echo "another WindowShade is running; skip the probe" >&2
  exit 2
fi
OUT="$ROOT/.build/face-fill-light"
mkdir -p "$OUT"
LOG="$OUT/run.txt"
rm -f "$LOG"
PREV_NOTCH=$(defaults read com.windowshade.prototype Notch.enabled 2>/dev/null || echo "__UNSET__")
restore() {
  case "$PREV_NOTCH" in
    "__UNSET__") defaults delete com.windowshade.prototype Notch.enabled 2>/dev/null || true ;;
    1|true|YES|yes) defaults write com.windowshade.prototype Notch.enabled -bool true ;;
    0|false|NO|no) defaults write com.windowshade.prototype Notch.enabled -bool false ;;
    *) defaults delete com.windowshade.prototype Notch.enabled 2>/dev/null || true ;;
  esac
  launchctl unsetenv WINDOWSHADE_PROBE_OUT 2>/dev/null || true
  pkill -9 -f "$APP/Contents/Resources/mediaremote-adapter.pl" 2>/dev/null || true
}
trap restore EXIT
defaults write com.windowshade.prototype Notch.enabled -bool YES
launchctl setenv WINDOWSHADE_PROBE_OUT "$LOG"
open -n "$APP" --args --face-fill-light-probe
for _ in $(seq 1 45); do
  grep -qE "PASS face-fill-light|FAIL face-fill-light" "$LOG" 2>/dev/null && break
  sleep 1
done
pkill -9 -f "$APP/Contents/MacOS/WindowShade --face-fill-light-probe" 2>/dev/null || true
cat "$LOG" 2>/dev/null || true
grep -q "^PASS face-fill-light" "$LOG"
