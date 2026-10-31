#!/bin/bash
# 退出后不留子进程（2026-10-31 决定 #50 e）：启动已签名的隔离构建，等它起好，记下它的全部后代进程，
# 用 AppleScript 的 quit 正常退出，再确认：App 本身退了、记下的后代一个都不在了、
# 已知的帮手（正在播放的适配器 perl、Claude／Codex 子进程、钩子帮手）没有残留，钩子 socket 文件也没留下。
# 先 `cd prototype && ./build.sh --stage`。没有隔离构建时打印 SKIP 并退出 0。
# 会启动并退出一份 WindowShade：日常用的那份在跑时拒绝（退出码 2），免得 quit 退掉日常那份。
# 用法：tests/run-leftover-process-check.sh [App 路径]（默认 .build/duo-validation/WindowShade.app）
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:-.build/duo-validation/WindowShade.app}
if [ ! -d "$APP" ]; then
  echo "SKIP leftover-process: $APP not found (run: cd prototype && ./build.sh --stage)"
  exit 0
fi
APP=$(cd "$APP" && pwd)
BIN="$APP/Contents/MacOS/WindowShade"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
if pgrep -x WindowShade >/dev/null; then
  echo "FAIL leftover-process: another WindowShade is already running; quit it first (this script quits by bundle id and must not hit your daily copy)" >&2
  exit 2
fi

descendants() { # 递归列出某个进程的全部后代进程号
  local parent=$1 child
  for child in $(pgrep -P "$parent" 2>/dev/null || true); do
    echo "$child"
    descendants "$child"
  done
}

open -n "$APP"
pid=""
for _ in $(seq 1 30); do
  pid=$(pgrep -f "^$BIN\$" | head -n 1 || true)
  [ -n "$pid" ] && break
  sleep 1
done
if [ -z "$pid" ]; then
  echo "FAIL leftover-process: the staged app did not start within 30 s" >&2
  exit 1
fi
echo "INFO leftover-process: app pid=$pid"
sleep 8 # 让正在播放的适配器等帮手有时间起来；没起来的话下面的检查就是空检查，会在结果里写明
children=$(descendants "$pid" | sort -u | tr '\n' ' ')
echo "INFO leftover-process: descendants before quit: ${children:-none}"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || echo "INFO leftover-process: osascript quit returned non-zero (the app may already be closing)"
gone=0
for _ in $(seq 1 20); do
  if ! kill -0 "$pid" 2>/dev/null; then gone=1; break; fi
  sleep 1
done
if [ "$gone" != 1 ]; then
  echo "FAIL leftover-process: the app did not quit within 20 s after the AppleScript quit (pid=$pid); leaving it running for you to look at" >&2
  exit 1
fi
echo "PASS leftover-process: the app quit gracefully"
sleep 3 # 帮手有几秒的收尾时间

fails=0
for child in $children; do
  if kill -0 "$child" 2>/dev/null; then
    echo "FAIL leftover-process: former child pid=$child is still alive: $(ps -o command= -p "$child" | cut -c1-160)"
    fails=$((fails + 1))
  fi
done
# 已知帮手的名字（命令行里带本 App 路径的才算，免得误伤用户自己的 claude／codex）。
for pattern in "$APP/Contents/Resources/mediaremote-adapter.pl" "$APP/Contents/Helpers/WindowShadeHook" "$APP/Contents/MacOS/WindowShade"; do
  found=$(pgrep -f "$pattern" || true)
  if [ -n "$found" ]; then
    echo "FAIL leftover-process: processes matching '$pattern' remain: $(echo "$found" | tr '\n' ' ')"
    fails=$((fails + 1))
  fi
done
# Claude／Codex 子进程：本 App 开的会话由它们的父进程（本 App）退出而结束；这里认“父进程变成 launchd 的孤儿”。
orphans=$(ps -axo pid=,ppid=,command= | awk -v bin="$BIN" '$2 == 1 && (index($0, "claude") || index($0, "codex")) && index($0, "WindowShade") {print $1}' || true)
if [ -n "$orphans" ]; then
  echo "FAIL leftover-process: orphaned claude/codex processes started by WindowShade: $(echo "$orphans" | tr '\n' ' ')"
  fails=$((fails + 1))
fi
if [ -S "$HOME/Library/Application Support/WindowShade/hooks.sock" ]; then
  echo "FAIL leftover-process: the hook server socket file is still there after quit"
  fails=$((fails + 1))
fi
if [ -z "$children" ]; then
  echo "INFO leftover-process: the app had no child processes before quit, so the child checks above were empty (turn on Now Playing / the conductor and run again for a stronger result)"
fi
if [ "$fails" -eq 0 ]; then
  echo "PASS leftover-process: no helper process or hook socket left behind"
  exit 0
fi
echo "FAIL leftover-process: $fails problem(s)"
exit 1
