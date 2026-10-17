#!/bin/bash
# 在虚拟机里跑 Phase 3 更新器检查的来宾一侧（由 run-updater-phase3.sh 传进来调用，不要在宿主上直接跑）。
# 不用 AppleScript／System Events／辅助功能，也不在 ssh 里截图（会卡在没人点的授权框，或 audit session 不允许）。
# 用法：updater-in-guest.sh prep | run <标签> <App 路径> <清单地址> <公钥或-> <plist|defaults> | cleanup
#   prep    存下 com.windowshade.prototype 的现有偏好
#   run     改测试副本的 Info.plist（ATS 放行 http、换公钥、SUFeedURL），ad-hoc 重签；偏好写成「定时检查已过期」，
#           启动后 Sparkle 自己在后台检查（SPUUpdater.m startUpdateCycle → scheduleNextUpdateCheck…：距上次检查已超过间隔就立刻查）；
#           最多等 150 秒，看 App 日志；再经 open 在图形会话里跑 VMWindowList.app 列窗口并截图；最后打印一行 RESULT
#   cleanup 退出 App、还原偏好、删掉传进来的 App 与工具
# 宿主保护：非虚拟机（kern.hv_vmm_present != 1）一律退出，什么都不改。每一处等待都有上限。
[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = 1 ] || { echo "REFUSED: not a virtual machine; nothing was changed" >&2; exit 3; }
DOM=com.windowshade.prototype
W="$HOME/wsqa-p3"
mkdir -p "$W/shots" "$W/logs"
cd "$W" || exit 1

quit_app() { # 先礼貌退出（不经 AppleScript：发 SIGTERM），最多等 6 秒再强杀
  pkill -x WindowShade 2>/dev/null
  for _ in 1 2 3 4 5 6; do pgrep -x WindowShade >/dev/null || return 0; sleep 1; done
  pkill -9 -x WindowShade; sleep 1
}

bounded() { # bounded 秒数 命令…：超时就杀，返回 124
  local limit=$1; shift
  "$@" & local pid=$!
  local t0=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - t0 >= limit )); then kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null; return 124; fi
    sleep 1
  done
  wait "$pid"
}

case "$1" in
prep)
  quit_app
  rm -f saved-defaults.plist
  if defaults export "$DOM" saved-defaults.plist 2>/dev/null && [ -s saved-defaults.plist ]; then echo "INFO guest: saved $DOM defaults"; else rm -f saved-defaults.plist; echo "INFO guest: $DOM had no defaults"; fi
  echo "INFO guest: macOS $(sw_vers -productVersion) $(sw_vers -buildVersion) console user=$(stat -f %Su /dev/console)"
  ;;
run)
  label=$2; app=$3; feed=$4; key=$5; via=$6
  [ -d "$app" ] || { echo "RESULT $label error=no-app"; exit 4; }
  plist="$app/Contents/Info.plist"; PB=/usr/libexec/PlistBuddy
  ver=$($PB -c 'Print CFBundleShortVersionString' "$plist" 2>/dev/null); build=$($PB -c 'Print CFBundleVersion' "$plist" 2>/dev/null)
  echo "INFO guest: $label app version=$ver build=$build signedfeed=$($PB -c 'Print SURequireSignedFeed' "$plist" 2>&1) origkey=$($PB -c 'Print SUPublicEDKey' "$plist" 2>&1) origfeed=$($PB -c 'Print SUFeedURL' "$plist" 2>&1)"
  quit_app
  # 偏好：清掉旧状态；已启动过、自动检查开、间隔 3600（Sparkle 的最小值）、上次检查在 5 天前 → 启动后立刻算「过期」，后台检查马上跑
  defaults delete "$DOM" >/dev/null 2>&1
  defaults write "$DOM" SUHasLaunchedBefore -bool true
  defaults write "$DOM" SUEnableAutomaticChecks -bool true
  defaults write "$DOM" SUScheduledCheckInterval -int 3600
  defaults write "$DOM" SULastCheckTime -date "$(date -u -v-5d '+%Y-%m-%d %H:%M:%S +0000')"
  # 测试副本：ATS 放行 http；清单是一次性测试密钥签的，公钥换成对应的
  $PB -c 'Delete :NSAppTransportSecurity' "$plist" >/dev/null 2>&1
  $PB -c 'Add :NSAppTransportSecurity dict' -c 'Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true' "$plist"
  [ "$key" = - ] || $PB -c "Set :SUPublicEDKey $key" "$plist"
  if [ "$via" = defaults ]; then defaults write "$DOM" SUFeedURL "$feed"; else $PB -c "Delete :SUFeedURL" "$plist" >/dev/null 2>&1; $PB -c "Add :SUFeedURL string $feed" "$plist"; fi
  if ! codesign --force --deep -s - "$app" >"$W/logs/$label-codesign.txt" 2>&1; then echo "RESULT $label error=resign-failed"; exit 5; fi
  log="$W/logs/$label-app.log"; : > "$log"; marker="$W/.marker-$label"; touch "$marker"
  open -n --env WINDOWSHADE_LOG_PATH="$log" "$app"
  for _ in $(seq 1 20); do pgrep -x WindowShade >/dev/null && break; sleep 1; done
  pgrep -x WindowShade >/dev/null || { echo "RESULT $label error=not-launched"; exit 6; }
  # 有界等待（最多 150 秒）：出现 found／error 就提前结束；只看到 updater started 的话再多等 45 秒（1.0.17 没有新版，日志里不会有 found）
  t0=$SECONDS; started_at=""
  while (( SECONDS - t0 < 150 )); do
    grep -Eq 'found [0-9]|error:' "$log" && break
    if [ -z "$started_at" ] && grep -qi 'updater started' "$log"; then started_at=$SECONDS; fi
    [ -n "$started_at" ] && (( SECONDS - started_at >= 45 )) && break
    pgrep -x WindowShade >/dev/null || break
    sleep 2
  done
  sleep 2
  # 窗口清单与截图：经 open 在图形会话里跑，输出读回来（和 run-in-guest.sh 的 display_tool 同一做法）
  wl="$W/logs/$label-windows.txt"; rm -f "$wl"
  bounded 40 open -n -W --stdout "$wl" --stderr "$wl" ./VMWindowList.app --args "$W/shots/$label.png" || echo "INFO guest: window list tool timed out"
  started=$(grep -ci 'updater started' "$log"); notstarted=$(grep -ci 'updater did not start' "$log")
  found=$(grep -E 'found [0-9]' "$log" | head -1 | tr ' ' '_'); err=$(grep -E 'error:' "$log" | head -1 | cut -c1-160 | tr ' ' '_')
  bad=$(grep -Eci 'downloading|extracting|installing|relaunching' "$log")
  ws=$(grep -c '^WIN WindowShade|' "$wl" 2>/dev/null)
  titles=$(grep '^WIN WindowShade|' "$wl" 2>/dev/null | awk -F'|' '$4==1 && $6!="" {print $6}' | paste -sd, - )
  alive=yes; pgrep -x WindowShade >/dev/null || alive=no
  crash=no; [ -n "$(find "$HOME/Library/Logs/DiagnosticReports" -name 'WindowShade*' -newer "$marker" 2>/dev/null | head -1)" ] && crash=yes
  cp -f "$HOME/Library/Logs/DiagnosticReports"/WindowShade* "$W/logs/" 2>/dev/null
  echo "RESULT $label version=$ver build=$build updater_started=$started updater_not_started=$notstarted found=${found:-none} error=${err:-none} installish_log_lines=$bad windows=${ws:-0} onscreen_titles=${titles:-none} alive=$alive crash=$crash"
  quit_app
  ;;
cleanup)
  quit_app
  defaults delete "$DOM" >/dev/null 2>&1
  if [ -s saved-defaults.plist ]; then defaults import "$DOM" saved-defaults.plist && echo "INFO guest: restored $DOM defaults"; fi
  rm -rf "$HOME/Applications/wsqa-p3-1016" "$HOME/Applications/wsqa-p3-1017" "$W/VMWindowList.app" /tmp/p3-1016.zip /tmp/p3-1017.zip /tmp/vmwl.zip /tmp/updater-in-guest.sh
  echo "INFO guest: cleanup done"
  ;;
*) echo "usage: updater-in-guest.sh prep|run|cleanup" >&2; exit 2 ;;
esac
