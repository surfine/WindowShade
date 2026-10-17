#!/bin/bash
# 在虚拟机里跑 Phase 3 更新器检查的来宾一侧（由 run-updater-phase3.sh 传进来调用，不要在宿主上直接跑）。
# 用法：updater-in-guest.sh prep | run <标签> <App 路径> <清单地址> <公钥或-> <plist|defaults> | cleanup
#   prep    存下 com.windowshade.prototype 的现有偏好，建 ~/wsqa-p3/{shots,ax,logs}
#   run     改一份「测试副本」的 Info.plist（ATS 放行 http、必要时换公钥、SUFeedURL），ad-hoc 重签，启动，触发「检查更新…」，
#           有界等待小窗，截图并导出 AX 文字，最后打印一行 AXRESULT 供宿主判读
#   cleanup 退出 App、还原偏好、删掉传进来的 App
# 宿主保护：非虚拟机（kern.hv_vmm_present != 1）一律退出，什么都不改。
[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = 1 ] || { echo "REFUSED: not a virtual machine; nothing was changed" >&2; exit 3; }
DOM=com.windowshade.prototype
W="$HOME/wsqa-p3"
mkdir -p "$W/shots" "$W/ax" "$W/logs"
cd "$W" || exit 1

quit_app() {
  osascript -e "tell application id \"$DOM\" to quit" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6; do pgrep -x WindowShade >/dev/null || return 0; sleep 1; done
  pkill -x WindowShade; sleep 1
}

# AppleScript 里要用的名称（中、英、繁体）。
DL_RE='打开下载页|開啟下載頁|Open the download page'
INSTALL_RE='更新并重新打开|更新並重新開啟|Update and reopen'
UPTODATE_RE='已经是最新版本|已經是最新版本|latest version'
ROLLBACK_RE='回到 ?[0-9]|Back to [0-9]'

as_run() { # 先直接跑 osascript，不行再经 launchctl asuser 进图形会话
  local f=$1 out
  out=$(osascript "$f" 2>&1); local rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -Eiq 'not allowed|1719|25211|-1743|connection invalid'; then
    out=$(launchctl asuser "$(id -u)" osascript "$f" 2>&1); rc=$?
  fi
  printf '%s\n' "$out"; return $rc
}

cat > trigger.applescript <<'AS'
set pats to {"检查更新", "Check for Updates", "檢查更新"}
tell application "System Events"
  if not (exists process "WindowShade") then return "NOPROCESS"
  tell process "WindowShade"
    set sb to missing value
    try
      set sb to menu bar item 1 of menu bar 2
    end try
    if sb is missing value then return "NOSTATUS"
    set res to "NOMENU"
    key down option
    try
      click sb
      delay 1
      repeat with mi in (menu items of menu 1 of sb)
        set nm to missing value
        try
          set nm to name of mi
        end try
        if nm is not missing value then
          repeat with p in pats
            if nm contains (contents of p) then
              click mi
              set res to "CLICKED"
              exit repeat
            end if
          end repeat
        end if
        if res is "CLICKED" then exit repeat
      end repeat
    on error e
      key up option
      return "ERROR " & e
    end try
    key up option
    if res is not "CLICKED" then key code 53
    return res
  end tell
end tell
AS

cat > dump.applescript <<'AS'
tell application "System Events"
  if not (exists process "WindowShade") then return "NOPROCESS"
  tell process "WindowShade"
    set out to ""
    repeat with w in windows
      set wn to ""
      try
        set wn to (name of w) as text
      end try
      set out to out & "WINDOW " & wn & linefeed
      try
        repeat with e in (entire contents of w)
          set r to ""
          set n to ""
          set v to ""
          try
            set r to (role of e) as text
          end try
          try
            set n to (name of e) as text
          end try
          try
            set v to (value of e) as text
          end try
          if r is not "" and (n is not "" or v is not "") then set out to out & "  " & r & " | " & n & " | " & v & linefeed
        end repeat
      end try
    end repeat
    return out
  end tell
end tell
AS

cat > settings.applescript <<'AS'
set pats to {"设置", "Settings", "設定"}
tell application "System Events"
  tell process "WindowShade"
    set sb to missing value
    try
      set sb to menu bar item 1 of menu bar 2
    end try
    if sb is missing value then return "NOSTATUS"
    set res to "NOMENU"
    try
      click sb
      delay 1
      repeat with mi in (menu items of menu 1 of sb)
        set nm to missing value
        try
          set nm to name of mi
        end try
        if nm is not missing value then
          repeat with p in pats
            if nm contains (contents of p) then
              click mi
              set res to "CLICKED"
              exit repeat
            end if
          end repeat
        end if
        if res is "CLICKED" then exit repeat
      end repeat
    on error e
      return "ERROR " & e
    end try
    if res is not "CLICKED" then key code 53
    return res
  end tell
end tell
AS

classify() { # 读 $1 里的 AX 文字，打印 install|download|uptodate|other|none
  local f=$1
  if ! grep -q '^WINDOW' "$f" 2>/dev/null; then echo none
  elif grep -Eiq "$INSTALL_RE" "$f"; then echo install
  elif grep -Eiq "$DL_RE" "$f"; then echo download
  elif grep -Eiq "$UPTODATE_RE" "$f"; then echo uptodate
  else echo other; fi
}

shot() { # 截图：先直接，不行经 asuser；失败只记一笔，不影响判定
  screencapture -x "$1" 2>/dev/null || launchctl asuser "$(id -u)" screencapture -x "$1" 2>/dev/null || echo "NOTE screencapture failed for $1"
}

case "$1" in
prep)
  quit_app
  rm -f saved-defaults.plist saved-absent
  if defaults export "$DOM" saved-defaults.plist 2>/dev/null && [ -s saved-defaults.plist ]; then echo "INFO guest: saved $DOM defaults"; else rm -f saved-defaults.plist; : > saved-absent; echo "INFO guest: $DOM had no defaults"; fi
  echo "INFO guest: macOS $(sw_vers -productVersion) $(sw_vers -buildVersion)"
  ;;
run)
  label=$2; app=$3; feed=$4; key=$5; via=$6
  [ -d "$app" ] || { echo "AXRESULT $label error=no-app"; exit 4; }
  plist="$app/Contents/Info.plist"; PB=/usr/libexec/PlistBuddy
  ver=$($PB -c 'Print CFBundleShortVersionString' "$plist" 2>/dev/null); build=$($PB -c 'Print CFBundleVersion' "$plist" 2>/dev/null)
  echo "INFO guest: $label app version=$ver build=$build signedfeed=$($PB -c 'Print SURequireSignedFeed' "$plist" 2>&1) origkey=$($PB -c 'Print SUPublicEDKey' "$plist" 2>&1) origfeed=$($PB -c 'Print SUFeedURL' "$plist" 2>&1)"
  quit_app
  # 偏好：清掉旧状态，让这次检查从干净状态开始；SULastCheckTime 设得很旧，让定时检查也会立刻触发
  defaults delete "$DOM" >/dev/null 2>&1
  defaults write "$DOM" SULastCheckTime -date "2000-01-01 00:00:00 +0000"
  # 测试副本：ATS 放行 http；清单签名是一次性测试密钥签的，所以公钥也换成对应的
  $PB -c 'Delete :NSAppTransportSecurity' "$plist" >/dev/null 2>&1
  $PB -c 'Add :NSAppTransportSecurity dict' -c 'Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true' "$plist"
  [ "$key" = - ] || $PB -c "Set :SUPublicEDKey $key" "$plist"
  if [ "$via" = defaults ]; then defaults write "$DOM" SUFeedURL "$feed"; else $PB -c "Delete :SUFeedURL" "$plist" >/dev/null 2>&1; $PB -c "Add :SUFeedURL string $feed" "$plist"; fi
  if ! codesign --force --deep -s - "$app" >"$W/logs/$label-codesign.txt" 2>&1; then echo "AXRESULT $label error=resign-failed"; exit 5; fi
  [ "$via" = defaults ] && [ -z "$($PB -c 'Print SUFeedURL' "$plist" 2>/dev/null)" ] && echo "INFO guest: $label has no SUFeedURL in Info.plist; only the user-defaults override is set (updater may not start)"
  log="$W/logs/$label-app.log"; : > "$log"; marker="$W/.marker-$label"; touch "$marker"
  open -n --env WINDOWSHADE_LOG_PATH="$log" "$app"
  for _ in $(seq 1 20); do pgrep -x WindowShade >/dev/null && break; sleep 1; done
  pgrep -x WindowShade >/dev/null || { echo "AXRESULT $label error=not-launched"; exit 6; }
  sleep 6
  started=$(grep -ci 'updater started' "$log"); notstarted=$(grep -ci 'updater did not start' "$log")
  drive=unavailable; trig=$(as_run trigger.applescript); echo "INFO guest: $label trigger -> $trig"
  case "$trig" in CLICKED) drive=ok ;; NOMENU|NOSTATUS) drive=nomenu ;; *) drive=unavailable ;; esac
  # 有界等待小窗（最多 50 秒），到出现可判读的内容为止
  cls=none; ax="$W/ax/$label.txt"
  for _ in $(seq 1 25); do
    sleep 2; as_run dump.applescript >"$ax" 2>&1
    cls=$(classify "$ax")
    case "$cls" in install|download|uptodate) break ;; esac
  done
  sleep 1; shot "$W/shots/$label.png"
  # 设置里有没有「回到 x」：能打开设置才算看过
  settings=notopened; rb=unknown
  sres=$(as_run settings.applescript); echo "INFO guest: $label settings -> $sres"
  if [ "$sres" = CLICKED ]; then
    sleep 3; as_run dump.applescript >"$W/ax/$label-settings.txt" 2>&1; shot "$W/shots/$label-settings.png"
    if grep -Eiq "$ROLLBACK_RE" "$W/ax/$label-settings.txt"; then rb=present
    elif grep -Eiq '当前版本|目前版本|Current version|Version [0-9]' "$W/ax/$label-settings.txt"; then rb=absent
    else rb=unknown; fi
  fi
  { /usr/bin/log show --last 5m --style compact --predicate 'process == "WindowShade" OR subsystem CONTAINS "sparkle"' 2>&1 | grep -iE 'sparkle|updat|feed|appcast|signed' | tail -80; } >"$W/logs/$label-oslog.txt" 2>&1
  alive=yes; pgrep -x WindowShade >/dev/null || alive=no
  crash=no; [ -n "$(find "$HOME/Library/Logs/DiagnosticReports" -name 'WindowShade*' -newer "$marker" 2>/dev/null | head -1)" ] && crash=yes
  cp -f "$HOME/Library/Logs/DiagnosticReports"/WindowShade* "$W/logs/" 2>/dev/null
  echo "AXRESULT $label version=$ver build=$build drive=$drive updater_started=$started updater_not_started=$notstarted class=$cls alive=$alive crash=$crash settings=$sres rollback=$rb"
  quit_app
  ;;
cleanup)
  quit_app
  defaults delete "$DOM" >/dev/null 2>&1
  if [ -s saved-defaults.plist ]; then defaults import "$DOM" saved-defaults.plist && echo "INFO guest: restored $DOM defaults"; fi
  rm -rf "$HOME/Applications/wsqa-p3-1016" "$HOME/Applications/wsqa-p3-1017" /tmp/p3-1016.zip /tmp/p3-1017.zip /tmp/updater-in-guest.sh
  echo "INFO guest: cleanup done"
  ;;
*) echo "usage: updater-in-guest.sh prep|run|cleanup" >&2; exit 2 ;;
esac
