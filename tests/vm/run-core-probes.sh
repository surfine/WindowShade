#!/bin/bash
# 在另外两个支持的 macOS 版本的虚拟机里跑核心探针（支持政策见 DEVELOPMENT.md「支持的系统版本」）。
# 用法：tests/vm/run-core-probes.sh lume@<虚拟机地址> [--setting 设置]… [--timeout-scale N] [--suite-timeout 秒] [探针组…]
#   --setting 可重复：autohide（V8 b）、stage-manager（V8 f／R19／V10）、mru-spaces-off／spans-displays-on（R30）、display:1280x800@1（V11）；只在虚拟机里改，跑完还原。
#   例：tests/vm/run-core-probes.sh lume@192.168.64.5 --setting autohide dock-scenarios
#       tests/vm/run-core-probes.sh lume@192.168.64.5 --setting display:1280x800@1 launchpad
# 先 cd prototype && ./build.sh --stage；虚拟机用外置 QA 盘的 Lume（RUNBOOK.md），客体里已授权辅助功能与屏幕录制、
# 已放好本机的 SSH 公钥。把签名构建与临时 App 用 ditto 打包传进去（不破坏签名），在客体的图形会话里逐组跑。
# 宿主保护：目标必须是 user@远端地址（拒绝本机），并且在改任何东西之前先问来宾 kern.hv_vmm_present 是否为 1；来宾脚本自己也会再查一次。
set -euo pipefail
cd "$(dirname "$0")/../.."
host=${1:?usage: run-core-probes.sh lume@<vm-ip> [--setting S]... [suites...]}; shift || true
settings=(); scale=3; suite_timeout=900; suites=()
while [ $# -gt 0 ]; do
  case "$1" in
    --setting) settings+=("${2:?--setting needs a value}"); shift 2 ;;
    --timeout-scale) scale=${2:?}; shift 2 ;;
    --suite-timeout) suite_timeout=${2:?}; shift 2 ;;
    *) suites+=("$1"); shift ;;
  esac
done
[ ${#suites[@]} -gt 0 ] || suites=(fold-timing restore-guard fold-unminimizable orphan wins browser-more)
for s in ${settings[@]+"${settings[@]}"}; do
  [[ "$s" =~ ^(autohide|stage-manager|mru-spaces-off|spans-displays-on|display:[0-9]+x[0-9]+@[12])$ ]] || { echo "未知的设置：$s" >&2; exit 2; }
done
[[ "$scale" =~ ^[0-9]+$ && "$suite_timeout" =~ ^[0-9]+$ ]] || { echo "--timeout-scale／--suite-timeout 要是整数" >&2; exit 2; }
case "$host" in
  *@*) addr=${host#*@} ;;
  *) echo "目标要写成 user@地址（拒绝没有用户名的目标，免得落到本机）" >&2; exit 2 ;;
esac
case "$addr" in
  localhost|127.*|::1|"$(hostname)"|"$(hostname -s)"|"$(hostname).local") echo "拒绝：目标是本机" >&2; exit 2 ;;
esac
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=15)
# 先确认对面真是虚拟机（有设置要改时必须；没有设置时也查，防止把宿主当来宾）。
vm=$(ssh "${ssh_opts[@]}" "$host" 'sysctl -n kern.hv_vmm_present' 2>/dev/null || true)
[ "$vm" = 1 ] || { echo "拒绝：$host 不是虚拟机（kern.hv_vmm_present=${vm:-无法连接}）" >&2; exit 3; }
# 临时 App 由本机任何一次 tests/run-glance-probe.sh 编出来。
[ -d .build/glance-tests/GlanceFixture.app ] || { echo "先在本机跑一次 tests/run-glance-probe.sh 编出临时 App" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ditto -c -k --keepParent .build/duo-validation/WindowShade.app "$tmp/ws.zip"
ditto -c -k --keepParent .build/glance-tests/GlanceFixture.app "$tmp/fx.zip"
files=("$tmp/ws.zip" "$tmp/fx.zip" tests/vm/run-in-guest.sh)
# 换显示模式要一个小工具（打成 .app 才能经 open 在来宾的图形会话里跑）。
if printf '%s\n' ${settings[@]+"${settings[@]}"} | grep -q '^display:'; then
  app="$tmp/VMDisplayMode.app"; mkdir -p "$app/Contents/MacOS"
  swiftc -target arm64-apple-macos15.0 tests/vm/vm-display-mode.swift -o "$app/Contents/MacOS/vm-display-mode"
  cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.windowshade.vm-display-mode</string>
<key>CFBundleName</key><string>VMDisplayMode</string>
<key>CFBundleExecutable</key><string>vm-display-mode</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
  codesign --force -s - "$app" >/dev/null 2>&1 || true
  ditto -c -k --keepParent "$app" "$tmp/dm.zip"; files+=("$tmp/dm.zip")
fi
ssh "${ssh_opts[@]}" "$host" "rm -f /tmp/dm.zip"
scp -q "${ssh_opts[@]}" "${files[@]}" "$host:/tmp/"
joined=$(IFS=,; echo "${settings[*]-}")
ssh "${ssh_opts[@]}" "$host" "mkdir -p ~/wsqa-run && cd ~/wsqa-run && rm -rf WindowShade.app GlanceFixture.app VMDisplayMode.app \
  && ditto -x -k /tmp/ws.zip . && ditto -x -k /tmp/fx.zip . && { [ ! -f /tmp/dm.zip ] || ditto -x -k /tmp/dm.zip .; } \
  && cp /tmp/run-in-guest.sh . && chmod +x run-in-guest.sh \
  && codesign --verify --deep --strict WindowShade.app && echo \"guest macOS \$(sw_vers -productVersion)\" \
  && WSQA_SETTINGS='$joined' WSQA_TIMEOUT_SCALE=$scale WSQA_SUITE_TIMEOUT=$suite_timeout WSQA_SOAK_ROUNDS=${WSQA_SOAK_ROUNDS:-100} ./run-in-guest.sh ${suites[*]}"
# 带回截图（V11 要看图标），有就拿。
out=".build/vm-results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out" && scp -q -r "${ssh_opts[@]}" "$host:wsqa-run/shots/." "$out/" 2>/dev/null && echo "screenshots: $out" || true
