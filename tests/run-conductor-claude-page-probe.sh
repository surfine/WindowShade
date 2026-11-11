#!/usr/bin/env bash
# 指挥页页面级验收：真 App 打开指挥页 → 切 Claude → 发送 → 转写 → 停止。
# 用 tests/fixtures/fake-claude.py，不发真实模型请求；需要开发签名证书。
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
OUT="$ROOT/.build/conductor-claude-page"
mkdir -p "$OUT"
LOG="$OUT/run.txt"
rm -f "$LOG"
PREV=$(defaults read com.windowshade.prototype Notch.enabled 2>/dev/null || echo "__UNSET__")
# 10-29 #4: the page must work with remote mode off; run with it off and put it back afterwards.
PREV_REMOTE=$(defaults read com.windowshade.prototype WindowShade.Input.RemoteMode 2>/dev/null || echo "__UNSET__")
restore() {
  case "$PREV_REMOTE" in
    "__UNSET__") defaults delete com.windowshade.prototype WindowShade.Input.RemoteMode 2>/dev/null || true ;;
    1|true|YES|yes) defaults write com.windowshade.prototype WindowShade.Input.RemoteMode -bool true ;;
    *) defaults write com.windowshade.prototype WindowShade.Input.RemoteMode -bool false ;;
  esac
  case "$PREV" in
    "__UNSET__") defaults delete com.windowshade.prototype Notch.enabled 2>/dev/null || true ;;
    1|true|YES|yes) defaults write com.windowshade.prototype Notch.enabled -bool true ;;
    0|false|NO|no) defaults write com.windowshade.prototype Notch.enabled -bool false ;;
  esac
  launchctl unsetenv WINDOWSHADE_CLAUDE_EXECUTABLE 2>/dev/null || true
  launchctl unsetenv WINDOWSHADE_PROBE_OUT 2>/dev/null || true
}
trap restore EXIT
defaults write com.windowshade.prototype Notch.enabled -bool YES
defaults write com.windowshade.prototype WindowShade.Input.RemoteMode -bool NO
echo "remote mode for this run: $(defaults read com.windowshade.prototype WindowShade.Input.RemoteMode)"
launchctl setenv WINDOWSHADE_CLAUDE_EXECUTABLE "$ROOT/tests/fixtures/fake-claude.py"
launchctl setenv WINDOWSHADE_PROBE_OUT "$LOG"
open -n "$APP" --args --conductor-claude-probe
for _ in $(seq 1 45); do
  grep -qE "PASS conductor-claude-page|FAIL conductor-claude-page" "$LOG" 2>/dev/null && break
  sleep 1
done
pkill -9 -f "$APP/Contents/MacOS/WindowShade --conductor-claude-probe" 2>/dev/null || true
cat "$LOG" 2>/dev/null || true
grep -q "^PASS conductor-claude-page" "$LOG"
