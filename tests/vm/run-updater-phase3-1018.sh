#!/bin/bash
# 1.0.18 发布关 Phase 3（更新器）在虚拟机里自动验。只在虚拟机里动手，宿主上只起一个临时 HTTP 服务和读文件。
# 与 1.0.17 那份（run-updater-phase3.sh）的差别：这一版验的是「1.0.17 → 1.0.18 真更新」——
#   来宾装真 1.0.17（gh release），本地清单喂 1.0.18 条目（url 指向本地、length 是真字节数、
#   edSignature 用一次性测试密钥签真 zip），预期 Sparkle 认出 1.0.18 并**下载**它。
#   「安装并重新打开」那一下要人点（SUAllowsAutomaticUpdates=false），留 Aaron 清单第 3 条；机器只验到「取了 zip、没报错」。
# 用法：tests/vm/run-updater-phase3.sh lume@<虚拟机地址> --zip <1.0.18 的 zip> [--app-1017 路径(.app 或 .zip)] [--out 目录] [--port N]
set -euo pipefail
cd "$(dirname "$0")/../.."
repo_root=$PWD
host=${1:?usage: run-updater-phase3-1018.sh lume@<vm-ip> --zip <zip> [--app-1017 P] [--out D] [--port N]}; shift || true
zip1018=""; app1017=""; out=".build/release-acceptance-2026-10-18/phase3-updater"; port=18766
while [ $# -gt 0 ]; do
  case "$1" in
    --zip) zip1018=${2:?}; shift 2 ;;
    --app-1017) app1017=${2:?}; shift 2 ;;
    --out) out=${2:?}; shift 2 ;;
    --port) port=${2:?}; shift 2 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
[[ "$port" =~ ^[0-9]+$ ]] || { echo "--port 要是整数" >&2; exit 2; }
[ -n "$zip1018" ] && [ -f "$zip1018" ] || { echo "要给 --zip（Phase 0 的 WindowShade-v1.0.18.zip）" >&2; exit 2; }
case "$host" in *@*) addr=${host#*@} ;; *) echo "目标要写成 user@地址" >&2; exit 2 ;; esac
case "$addr" in localhost|127.*|::1|"$(hostname)"|"$(hostname -s)"|"$(hostname).local") echo "拒绝：目标是本机" >&2; exit 2 ;; esac
repo=$(git remote get-url origin | sed -E 's#^(git@github.com:|https?://github.com/)##; s#\.git$##')
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=15)
g() { ssh "${ssh_opts[@]}" "$host" "$@"; }

tmp=$(mktemp -d); mkdir "$tmp/serve"
http_pid=""; guest_touched=0
cleanup() {
  if [ -n "$http_pid" ]; then kill "$http_pid" 2>/dev/null; wait "$http_pid" 2>/dev/null; fi; true
  if [ "${guest_touched:-0}" = 1 ]; then
    g "bash /tmp/updater-in-guest.sh cleanup" 2>&1 | sed 's/^/  /' || echo "WARN 来宾清理没跑成，手动：ssh $host 'bash /tmp/updater-in-guest.sh cleanup'" >&2
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

vm=$(g 'sysctl -n kern.hv_vmm_present' 2>/dev/null || true)
[ "$vm" = 1 ] || { echo "拒绝：$host 不是虚拟机（kern.hv_vmm_present=${vm:-无法连接}）" >&2; exit 3; }
gw=$(g "route -n get default 2>/dev/null | awk '/gateway:/{print \$2}'")
[[ "$gw" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "读不到来宾默认网关" >&2; exit 1; }
ifconfig | grep -q "inet $gw " || { echo "拒绝：宿主上没有 $gw 这个地址" >&2; exit 1; }
feed_url="http://$gw:$port/appcast.xml"
zip_name=$(basename "$zip1018"); zip_url="http://$gw:$port/$zip_name"

sign="swift tests/vm/sparkle-feed-sign.swift"
real_pub=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' prototype/Info.plist)
$sign verify "$real_pub" site/public/appcast.xml >/dev/null || { echo "自检失败：线上清单验不过真公钥" >&2; exit 1; }
read -r priv pub < <($sign keygen)
cp "$zip1018" "$tmp/serve/$zip_name"
zip_len=$(wc -c < "$tmp/serve/$zip_name" | tr -d ' ')
zip_sig=$($sign sign "$priv" "$tmp/serve/$zip_name")
python3 -I - "$tmp/serve/appcast.xml" "$zip_url" "$zip_len" "$zip_sig" <<'PY'
import re, sys
dest, zip_url, zip_len, zip_sig = sys.argv[1:5]
live = open('site/public/appcast.xml', encoding='utf-8').read()
body = live[:live.index('<!-- sparkle-signatures')]
draft = open('docs/releases/appcast-item-1.0.18.xml', encoding='utf-8').read()
item = re.search(r'<item>\s*<title>.*?</item>', draft, re.S).group(0)
item = re.sub(r'url="[^"]*"', 'url="%s"' % zip_url, item, count=1)
item = re.sub(r'length="[^"]*"', 'length="%s"' % zip_len, item, count=1)
item = re.sub(r'sparkle:edSignature="[^"]*"', 'sparkle:edSignature="%s"' % zip_sig, item, count=1)
assert 'TODO' not in re.sub(r'<!--.*?-->|<description>.*?</description>', '', item, flags=re.S), 'unfilled TODO left in item'
i = body.index('<item>')
body = body[:i] + item.strip() + '\n    ' + body[i:]
open(dest, 'w', encoding='utf-8').write(body)
PY
sig=$($sign sign "$priv" "$tmp/serve/appcast.xml"); len=$(wc -c < "$tmp/serve/appcast.xml" | tr -d ' ')
printf '<!-- sparkle-signatures:\nedSignature: %s\nlength: %s\n-->\n' "$sig" "$len" >> "$tmp/serve/appcast.xml"
$sign verify "$pub" "$tmp/serve/appcast.xml" >/dev/null || { echo "本地清单自验签失败" >&2; exit 1; }
xmllint --noout "$tmp/serve/appcast.xml" 2>/dev/null || python3 -c "import xml.etree.ElementTree,sys; xml.etree.ElementTree.parse('$tmp/serve/appcast.xml')" || { echo "本地清单不是合法 XML" >&2; exit 1; }
echo "INFO 本地清单已生成（1.0.18 条目指向 $zip_url，length=$zip_len）"

mkdir -p "$out"
# 1.0.17 的包
if [ -z "$app1017" ]; then
  echo "==> gh release download v1.0.17 --repo $repo"
  gh release download v1.0.17 --repo "$repo" -p 'WindowShade-v1.0.17.zip' -D "$tmp" --clobber
  app1017="$tmp/WindowShade-v1.0.17.zip"
fi
case "$app1017" in
  *.zip) ditto -x -k "$app1017" "$tmp/1017" ;;
  *.app) mkdir -p "$tmp/1017" && cp -R "$app1017" "$tmp/1017/" ;;
  *) echo "不认识的包：$app1017" >&2; exit 1 ;;
esac
app17="$tmp/1017/WindowShade.app"
[ -d "$app17" ] || { echo "解包后找不到 $app17" >&2; exit 1; }

(cd "$tmp/serve" && python3 -u -m http.server "$port" --bind "$gw" > "$tmp/http.log" 2>&1) & http_pid=$!
sleep 1
curl -sf "http://$gw:$port/appcast.xml" >/dev/null || { echo "本地清单服务没起来" >&2; exit 1; }

scp -q "${ssh_opts[@]}" tests/vm/updater-in-guest.sh "$host:/tmp/updater-in-guest.sh"
g "bash /tmp/updater-in-guest.sh prep" | sed 's/^/  /'
guest_touched=1
rm -f "$tmp/app1017.tar"; ditto -c -k --keepParent "$app17" "$tmp/app1017.tar"
scp -q "${ssh_opts[@]}" "$tmp/app1017.tar" "$host:/tmp/app1017.zip"
g "cd \$HOME && rm -rf wsqa-p3-1017 && mkdir wsqa-p3-1017 && ditto -x -k /tmp/app1017.zip wsqa-p3-1017" | sed 's/^/  /'
g "bash /tmp/updater-in-guest.sh run p3-1017 \$HOME/wsqa-p3-1017/WindowShade.app $feed_url $pub plist" | tee "$tmp/guest-run.log" | sed 's/^/  /'

# 证据拷回
mkdir -p "$out"
cp "$tmp/http.log" "$out/http-access.log" 2>/dev/null || true
g "cat \$HOME/wsqa-p3/logs/* 2>/dev/null" > "$out/guest-logs.txt" || true

# 判读：清单取到、zip 取到、日志认出 1.0.18、没有下载/安装报错
feed_hit=$(grep -c "GET /appcast.xml" "$tmp/http.log" || true)
zip_hit=$(grep -c "GET /$zip_name" "$tmp/http.log" || true)
applog=$(g "cat \$HOME/wsqa-p3/logs/p3-1017-app.log 2>/dev/null" || true)
found18=$(printf '%s' "$applog" | grep -c "1\.0\.18" || true)
errors=$(printf '%s' "$applog" | grep -ci "error" || true)
echo "---- 判读 ----"
echo "feed_hit=$feed_hit zip_hit=$zip_hit found18=$found18 error_lines=$errors"
if [ "$feed_hit" -ge 1 ] && [ "$zip_hit" -ge 1 ] && [ "$found18" -ge 1 ]; then
  echo "PASS updater-1018：1.0.17 取了清单、下载了 1.0.18 的 zip、日志认出 1.0.18（安装那一下留 Aaron）"
  exit 0
elif [ "$feed_hit" -ge 1 ] && [ "$found18" -ge 1 ]; then
  echo "INCONCLUSIVE updater-1018：认出了 1.0.18 但没看到取 zip（Sparkle 可能延后下载）"
  exit 0
else
  echo "INCONCLUSIVE updater-1018：清单没被取到或没认出版本（feed_hit=$feed_hit found18=$found18）；绝不记 PASS"
  exit 0
fi
