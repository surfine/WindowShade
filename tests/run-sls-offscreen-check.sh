#!/bin/bash
# F7 真机取证：privateOffscreen 的收起验证要看窗口服务器的外框，不能只看 AX。
# 探针用探针进程自己的两扇临时窗口走真实入口（privateSLSOffscreenHide +
# observeFoldHide + FoldVerifier），三方读数与判定都留在 stdout。
# 需要先 `cd prototype && WINDOWSHADE_CODESIGN_IDENTITY='…' ./build.sh --stage`。
# 不碰 Finder、浏览器、未保存的窗口，也不碰 /Applications 里每天在用的那份。
set -euo pipefail
cd "$(dirname "$0")/.."
APP=.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade
"$APP" --sls-offscreen-check
