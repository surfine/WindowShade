#!/bin/bash
# 菜单栏共存检查（规格 O9）：在 QA 虚拟机的「克隆」里装 Ice 和 Thaw，和 WindowShade 一起跑，看状态栏图标会不会抖。
# 用法：tests/vm/install-menubar-managers.sh lume@<克隆虚拟机地址> [--rebuilds N] [--fold-cmd '来宾里改变折叠数的命令'] [--keep]
#   --rebuilds N   轮流激活别的 App 来触发 N 次菜单重建（默认 12）；每轮之间采样图标位置
#   --fold-cmd C   在来宾里执行的命令，用来让折叠数变化（例如跑一个探针、或发全局快捷键的小工具）；
#                  不给就只测「重建 N 次图标位置稳不稳」，并明说没测折叠数变化
#   --keep         跑完不卸载 Ice／Thaw（默认卸载并还原它们的偏好）
# 先 cd prototype && ./build.sh --stage（得到 .build/duo-validation/WindowShade.app）。宿主需要 gh、ditto、swiftc。
# 宿主保护：目标必须是 user@远端地址（拒绝本机），改任何东西之前先问来宾 kern.hv_vmm_present 是否为 1；来宾脚本自己再查一次。
# Ice／Thaw 在宿主上用 gh release download 下到临时目录，再 ditto 传进来宾，装到 ~/Applications，永远不在宿主上启动。
# 它们首次启动会要辅助功能／屏幕录制授权；克隆里没预先授权的话，授权框要人点（脚本只报告，不替你点）。
set -euo pipefail
cd "$(dirname "$0")/../.."
host=${1:?usage: install-menubar-managers.sh lume@<clone-vm-ip> [--rebuilds N] [--fold-cmd CMD] [--keep]}; shift || true
rebuilds=12; fold_cmd=""; keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --rebuilds) rebuilds=${2:?--rebuilds needs a number}; shift 2 ;;
    --fold-cmd) fold_cmd=${2:?--fold-cmd needs a command}; shift 2 ;;
    --keep) keep=1; shift ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
[[ "$rebuilds" =~ ^[0-9]+$ ]] || { echo "--rebuilds 要是整数" >&2; exit 2; }
case "$host" in
  *@*) addr=${host#*@} ;;
  *) echo "目标要写成 user@地址（拒绝没有用户名的目标，免得落到本机）" >&2; exit 2 ;;
esac
case "$addr" in
  localhost|127.*|::1|"$(hostname)"|"$(hostname -s)"|"$(hostname).local") echo "拒绝：目标是本机" >&2; exit 2 ;;
esac
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=15)
vm=$(ssh "${ssh_opts[@]}" "$host" 'sysctl -n kern.hv_vmm_present' 2>/dev/null || true)
[ "$vm" = 1 ] || { echo "拒绝：$host 不是虚拟机（kern.hv_vmm_present=${vm:-无法连接}）" >&2; exit 3; }
command -v gh >/dev/null || { echo "宿主需要 gh" >&2; exit 1; }
[ -d .build/duo-validation/WindowShade.app ] || { echo "先在本机跑 prototype/build.sh --stage" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/dl-ice" "$tmp/dl-thaw" "$tmp/x-ice" "$tmp/x-thaw"
# 下载在宿主；只下 .zip，解压后核对确实是 .app。
gh release download -R jordanbaird/Ice --pattern 'Ice.zip' --dir "$tmp/dl-ice"
gh release download -R thaw-app/Thaw --pattern 'Thaw_*.zip' --dir "$tmp/dl-thaw"
ditto -x -k "$tmp"/dl-ice/Ice.zip "$tmp/x-ice"
ditto -x -k "$tmp"/dl-thaw/Thaw_*.zip "$tmp/x-thaw"
ice_app=$(find "$tmp/x-ice" -maxdepth 2 -name '*.app' | head -1); thaw_app=$(find "$tmp/x-thaw" -maxdepth 2 -name '*.app' | head -1)
[ -n "$ice_app" ] && [ -n "$thaw_app" ] || { echo "下载的压缩包里没找到 .app" >&2; exit 1; }
echo "INFO host: Ice $(defaults read "$ice_app/Contents/Info" CFBundleShortVersionString), Thaw $(defaults read "$thaw_app/Contents/Info" CFBundleShortVersionString)"

# 位置采样小工具打成 .app，才能经 open 在来宾的图形会话里跑。
tool="$tmp/VMStatusFrames.app"; mkdir -p "$tool/Contents/MacOS"
swiftc -target arm64-apple-macos15.0 tests/vm/vm-statusitem-frames.swift -o "$tool/Contents/MacOS/vm-statusitem-frames"
cat > "$tool/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.windowshade.vm-statusitem-frames</string>
<key>CFBundleName</key><string>VMStatusFrames</string>
<key>CFBundleExecutable</key><string>vm-statusitem-frames</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$tool" >/dev/null 2>&1 || true
ditto -c -k --keepParent "$tool" "$tmp/tool.zip"
ditto -c -k --keepParent .build/duo-validation/WindowShade.app "$tmp/ws.zip"
ditto -c -k --keepParent "$ice_app" "$tmp/ice.zip"
ditto -c -k --keepParent "$thaw_app" "$tmp/thaw.zip"

ssh "${ssh_opts[@]}" "$host" "rm -f /tmp/mb-*.zip"
scp -q "${ssh_opts[@]}" "$tmp/ws.zip" "$host:/tmp/mb-ws.zip"
scp -q "${ssh_opts[@]}" "$tmp/tool.zip" "$host:/tmp/mb-tool.zip"
scp -q "${ssh_opts[@]}" "$tmp/ice.zip" "$host:/tmp/mb-ice.zip"
scp -q "${ssh_opts[@]}" "$tmp/thaw.zip" "$host:/tmp/mb-thaw.zip"

# 来宾一侧：经 ssh 的 stdin 送进去执行。
rc=0
ssh "${ssh_opts[@]}" "$host" "REBUILDS=$rebuilds KEEP=$keep FOLD_CMD=$(printf %q "$fold_cmd") bash -s" <<'GUEST' || rc=$?
[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = 1 ] || { echo "REFUSED: not a virtual machine; nothing was changed" >&2; exit 3; }
W="$HOME/wsqa-mb"; A="$HOME/Applications"; DOM=com.windowshade.prototype
mkdir -p "$W/shots" "$W/logs" "$A"; cd "$W" || exit 1
quit() { pkill -x "$1" 2>/dev/null; for _ in 1 2 3 4 5 6; do pgrep -x "$1" >/dev/null || return 0; sleep 1; done; pkill -9 -x "$1"; sleep 1; }
bounded() { local limit=$1; shift; "$@" & local pid=$!; local t0=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do (( SECONDS - t0 >= limit )) && { kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null; return 124; }; sleep 1; done; wait "$pid"; }
for n in WindowShade Ice Thaw; do quit "$n"; done
rm -rf VMStatusFrames.app WindowShade.app "$A/Ice.app" "$A/Thaw.app"
ditto -x -k /tmp/mb-tool.zip . && ditto -x -k /tmp/mb-ws.zip . && ditto -x -k /tmp/mb-ice.zip "$A" && ditto -x -k /tmp/mb-thaw.zip "$A"
codesign --verify --deep --strict WindowShade.app && echo "INFO guest: macOS $(sw_vers -productVersion), WindowShade signature ok"
# 把状态栏图标的存档偏好清掉，每次都从「第一次启动」开始比。
defaults delete "$DOM" "NSStatusItem Preferred Position WindowShadeStatusItem" >/dev/null 2>&1
defaults delete "$DOM" "NSStatusItem Visible WindowShadeStatusItem" >/dev/null 2>&1
log="$W/logs/app.log"; : > "$log"
open -a "$A/Ice.app"; open -a "$A/Thaw.app"; sleep 8
open -n --env WINDOWSHADE_LOG_PATH="$log" WindowShade.app
for _ in $(seq 1 20); do pgrep -x WindowShade >/dev/null && break; sleep 1; done
pgrep -x WindowShade >/dev/null || { echo "RESULT error=ws-not-launched"; exit 6; }
sleep 5
frames() { # frames 标签 秒数
  local out="$W/logs/frames-$1.txt"; rm -f "$out"
  bounded $(( $2 + 30 )) open -n -W --stdout "$out" --stderr "$out" ./VMStatusFrames.app --args WindowShade "$2" 200 || echo "INFO guest: frames tool timed out ($1)"
  grep '^SUMMARY' "$out" 2>/dev/null || echo "SUMMARY none($1)"; }
shot() { screencapture -x "$W/shots/$1.png" 2>/dev/null || echo "INFO guest: screencapture unavailable ($1)"; }
shot before
base=$(frames idle 4)
# 激活别的 App 来触发 WindowShade 的菜单重建；采样在后台跑，同时轮流激活。
( frames rebuilds $(( REBUILDS * 2 + 4 )) >"$W/logs/rebuilds-summary.txt" ) &
sampler=$!
sleep 3
for i in $(seq 1 "$REBUILDS"); do
  if (( i % 2 )); then open -a TextEdit; else open -a Finder; fi
  sleep 2
done
wait "$sampler"
reb=$(cat "$W/logs/rebuilds-summary.txt")
fold="not-run(no --fold-cmd)"; after=""
if [ -n "$FOLD_CMD" ]; then
  ( frames fold 14 >"$W/logs/fold-summary.txt" ) & sampler=$!
  sleep 3; bounded 90 bash -c "$FOLD_CMD"; fold="ran rc=$?"
  wait "$sampler"; after=$(cat "$W/logs/fold-summary.txt")
fi
shot after
alive=yes; pgrep -x WindowShade >/dev/null || alive=no
mgrs="Ice=$(pgrep -x Ice >/dev/null && echo up || echo down),Thaw=$(pgrep -x Thaw >/dev/null && echo up || echo down)"
crash=no; [ -n "$(find "$HOME/Library/Logs/DiagnosticReports" -name 'WindowShade*' -mmin -30 2>/dev/null | head -1)" ] && crash=yes
echo "RESULT idle: $base"
echo "RESULT rebuilds($REBUILDS): $reb"
echo "RESULT fold: $fold ${after:+| $after}"
echo "RESULT alive=$alive managers=$mgrs crash=$crash"
echo "HINT 通过判据：rebuilds/fold 的 SUMMARY 里 missing=0 且 distinctRightEdges=1（宽度可以变，右边缘和 y 不能漂）；Ice／Thaw 起来了（up）。看 shots/before.png 与 after.png 确认刘海与图标没被挤掉。"
quit WindowShade; quit Ice; quit Thaw
if [ "$KEEP" != 1 ]; then
  rm -rf "$A/Ice.app" "$A/Thaw.app" VMStatusFrames.app
  defaults delete com.jordanbaird.Ice >/dev/null 2>&1; defaults delete com.stonerl.Thaw >/dev/null 2>&1; defaults delete "$DOM" "NSStatusItem Preferred Position WindowShadeStatusItem" >/dev/null 2>&1
  echo "INFO guest: managers removed"
fi
rm -f /tmp/mb-*.zip
GUEST
out=".build/vm-results/menubar-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out" && scp -q -r "${ssh_opts[@]}" "$host:wsqa-mb/shots/." "$host:wsqa-mb/logs/." "$out/" 2>/dev/null && echo "screenshots+logs: $out" || true
exit $rc
