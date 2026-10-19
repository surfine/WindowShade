#!/usr/bin/env bash
# 刘海审批卡的页面级验收：真 App 里放一张假的 PermissionRequest，检查卡片尺寸/按钮/可输入，
# 再收走。没有 Claude Code、没有 Touch ID、没有模型请求。需要开发签名证书。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/prototype"
WINDOWSHADE_CODESIGN_IDENTITY="${WINDOWSHADE_CODESIGN_IDENTITY:-Apple Development: openkams@gmail.com (G3TN2MBQ2Q)}" \
  ./build.sh --stage
APP="$ROOT/.build/duo-validation/WindowShade.app"
# 不和正在用的 WindowShade 抢刘海/开关/socket；有一个在跑就跳过。
if pgrep -x WindowShade >/dev/null 2>&1; then
  echo "another WindowShade is running; skip the probe" >&2
  exit 2
fi
OUT="$ROOT/.build/hook-approval-page"
mkdir -p "$OUT"
LOG="$OUT/run.txt"
rm -f "$LOG"
SOCK="$HOME/Library/Application Support/WindowShade/hooks.sock"
HAD_SOCKET=0
[ -S "$SOCK" ] && HAD_SOCKET=1
PREV_NOTCH=$(defaults read com.windowshade.prototype Notch.enabled 2>/dev/null || echo "__UNSET__")
PREV_CODING=$(defaults read com.windowshade.prototype WindowShade.Conductor.CodingSessions 2>/dev/null || echo "__UNSET__")
restore_bool() {
  local key="$1" value="$2"
  case "$value" in
    "__UNSET__") defaults delete com.windowshade.prototype "$key" 2>/dev/null || true ;;
    1|true|YES|yes) defaults write com.windowshade.prototype "$key" -bool true ;;
    0|false|NO|no) defaults write com.windowshade.prototype "$key" -bool false ;;
    *) defaults delete com.windowshade.prototype "$key" 2>/dev/null || true ;;
  esac
}
restore() {
  restore_bool Notch.enabled "$PREV_NOTCH"
  restore_bool WindowShade.Conductor.CodingSessions "$PREV_CODING"
  launchctl unsetenv WINDOWSHADE_PROBE_OUT 2>/dev/null || true
  # 探针被 SIGKILL 后，它起的媒体来源子进程可能还挂着。
  pkill -9 -f "$APP/Contents/Resources/mediaremote-adapter.pl" 2>/dev/null || true
  # 探针自己被 SIGKILL 结束，来不及删 socket；开跑前没有它才清掉。
  if [ "$HAD_SOCKET" = "0" ] && [ -S "$SOCK" ]; then rm -f "$SOCK"; fi
}
trap restore EXIT
defaults write com.windowshade.prototype Notch.enabled -bool YES
defaults write com.windowshade.prototype WindowShade.Conductor.CodingSessions -bool YES
launchctl setenv WINDOWSHADE_PROBE_OUT "$LOG"
open -n "$APP" --args --hook-approval-probe
for _ in $(seq 1 45); do
  grep -qE "PASS hook-approval-page|FAIL hook-approval-page" "$LOG" 2>/dev/null && break
  sleep 1
done
pkill -9 -f "$APP/Contents/MacOS/WindowShade --hook-approval-probe" 2>/dev/null || true
cat "$LOG" 2>/dev/null || true
grep -q "^PASS hook-approval-page" "$LOG"
