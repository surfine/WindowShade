#!/bin/bash
# 规格 N1：快捷指令动作的自动检查（不需要人、不动鼠标、不开窗口、不改系统）。
#   bash tests/run-n1-shortcuts-check.sh [WindowShade.app 路径] [--registered]
# (a) 读包里的 Metadata.appintents：恰好 7 个可发现动作，且每个的标题／说明在 en／zh-Hans／zh-Hant 都有、不为空；
#     并和源码 prototype/App/WindowShadeIntents.swift 里的 AppIntent 结构体逐个对上。
# (b) 只读查系统快捷指令的动作索引（~/Library/Shortcuts/ToolKit/Tools-active，复制到临时目录再查）：
#     这个包的 bundle id 下登记了几个动作。默认只报告（INFO/SKIP）；加 --registered 时没登记就算 FAIL。
#     注：`shortcuts list` 只列用户自己的快捷指令，列不出 App 提供的动作；「快捷指令」App 里搜得到，
#     最终只能由该 App 界面确认（见脚本末尾 SUMMARY 的说明）。
set -uo pipefail
cd "$(dirname "$0")/.."
APP=""; REQUIRE_REG=0
for a in "$@"; do case "$a" in --registered) REQUIRE_REG=1 ;; *) APP="$a" ;; esac; done
APP="${APP:-.build/duo-validation/WindowShade.app}"
exec python3 -I tests/n1-shortcuts-check.py "$APP" "$REQUIRE_REG" "prototype/App/WindowShadeIntents.swift"
