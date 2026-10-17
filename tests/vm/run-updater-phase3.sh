#!/bin/bash
# 1.0.17 发布关 Phase 3（更新器）在虚拟机里自动验。只在虚拟机里动手，宿主上只起一个临时 HTTP 服务和读文件。
# 用法：tests/vm/run-updater-phase3.sh lume@<虚拟机地址> [--app-1016 路径(.app 或 .zip)] [--app-1017 路径(.app)]
#                                       [--out 目录] [--port N] [--feed-via plist|defaults] [--repo owner/repo] [--dry-run]
# 做什么：
#   1. 拒绝非虚拟机目标（同 run-core-probes.sh：user@远端地址、拒绝本机、先问来宾 kern.hv_vmm_present）。
#   2. 取 1.0.16 发布包（默认 gh release download v1.0.16；--app-1016 可覆盖），ditto 进来宾 ~/Applications 解包。
#   3. 在宿主上造本地清单：site/public/appcast.xml ＋ 1.0.17 草稿条目（插在 1.0.16 之前，url 指向本地、永远不会被下载，
#      length=1，edSignature 是 64 个零字节的占位）。
#      1.0.16 的 Info.plist 有 SURequireSignedFeed=true 和 SUVerifyUpdateBeforeExtraction=true，改过的清单过不了线上公钥，
#      所以清单用一次性测试私钥签（Sparkle 格式，已用线上清单和真公钥交叉验证过），来宾里的「测试副本」把 SUPublicEDKey
#      换成对应测试公钥，并加 ATS 放行 http（1.0.16 没有 NSAppTransportSecurity，http 清单会被系统拦）。副本 ad-hoc 重签。
#      真私钥、钥匙串一律不碰。
#   4. 宿主在虚拟机网桥地址（来宾默认网关）上起 python3 http.server，只在本次运行期间。
#   5. 来宾里：1.0.16 指向本地清单，触发「检查更新…」，导出 AX 文字与截图；期望「这一版要手动下载」＋打开下载页，不是安装。
#      再对 1.0.17 同样做一遍，期望「已是最新」、不崩溃、没有「回到 1.0.16」。
#   6. 还原来宾偏好、退出 App、删掉拷进去的 App、停 HTTP 服务；证据拷回 --out（默认 .build/release-acceptance-2026-10-17/phase3-updater/）。
# 判读：PASS／FAIL／INCONCLUSIVE。清单没被取到、菜单驱动不了、更新器没启动，都是 INCONCLUSIVE，绝不记 PASS；
#      驱动成功但没有提示、出现安装按钮、或本地 zip 地址被请求，是 FAIL。
set -euo pipefail
cd "$(dirname "$0")/../.."
repo_root=$PWD
host=${1:?usage: run-updater-phase3.sh lume@<vm-ip> [--app-1016 P] [--app-1017 P] [--out D] [--port N] [--feed-via plist|defaults] [--dry-run]}; shift || true
app1016=""; app1017=""; out=".build/release-acceptance-2026-10-17/phase3-updater"; port=18765; via=plist; repo=""; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --app-1016) app1016=${2:?}; shift 2 ;;
    --app-1017) app1017=${2:?}; shift 2 ;;
    --out) out=${2:?}; shift 2 ;;
    --port) port=${2:?}; shift 2 ;;
    --feed-via) via=${2:?}; shift 2 ;;
    --repo) repo=${2:?}; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
[[ "$port" =~ ^[0-9]+$ ]] || { echo "--port 要是整数" >&2; exit 2; }
[[ "$via" =~ ^(plist|defaults)$ ]] || { echo "--feed-via 只能是 plist 或 defaults" >&2; exit 2; }
case "$host" in
  *@*) addr=${host#*@} ;;
  *) echo "目标要写成 user@地址（拒绝没有用户名的目标，免得落到本机）" >&2; exit 2 ;;
esac
case "$addr" in
  localhost|127.*|::1|"$(hostname)"|"$(hostname -s)"|"$(hostname).local") echo "拒绝：目标是本机" >&2; exit 2 ;;
esac
if [ -z "$repo" ]; then
  repo=$(git remote get-url origin | sed -E 's#^(git@github.com:|https?://github.com/)##; s#\.git$##')
fi
[ -n "$app1017" ] || app1017=".build/duo-validation/WindowShade.app"
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=15)
g() { ssh "${ssh_opts[@]}" "$host" "$@"; }   # 来宾命令

tmp=$(mktemp -d); mkdir "$tmp/serve" "$tmp/dl"
http_pid=""
cleanup() {
  [ -n "$http_pid" ] && kill "$http_pid" 2>/dev/null || true
  if [ "$dry" = 0 ] && [ "${guest_touched:-0}" = 1 ]; then
    g "bash /tmp/updater-in-guest.sh cleanup" 2>&1 | sed 's/^/  /' || echo "WARN 来宾清理没跑成，手动：ssh $host 'bash /tmp/updater-in-guest.sh cleanup'" >&2
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
verdicts=()
say() { echo "$@"; }
record() { verdicts+=("$1"); echo "$1"; }

# --- 1. 宿主保护 ---
if [ "$dry" = 1 ]; then
  gw=192.168.64.1; say "DRY-RUN：不连 ssh；网桥地址按 $gw 假设"
else
  vm=$(g 'sysctl -n kern.hv_vmm_present' 2>/dev/null || true)
  [ "$vm" = 1 ] || { echo "拒绝：$host 不是虚拟机（kern.hv_vmm_present=${vm:-无法连接}）" >&2; exit 3; }
  gw=$(g "route -n get default 2>/dev/null | awk '/gateway:/{print \$2}'")
  [[ "$gw" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "读不到来宾默认网关（得到：${gw:-空}）" >&2; exit 1; }
  ifconfig | grep -q "inet $gw " || { echo "拒绝：宿主上没有 $gw 这个地址，不能在它上面起服务（不改成监听全部网卡）" >&2; exit 1; }
fi
feed_url="http://$gw:$port/appcast.xml"
zip_url="http://$gw:$port/WindowShade-v1.0.17.zip"

# --- 2. 一次性测试密钥与本地清单 ---
sign="swift tests/vm/sparkle-feed-sign.swift"
real_pub=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' prototype/Info.plist)
$sign verify "$real_pub" site/public/appcast.xml >/dev/null || { echo "自检失败：线上清单验不过真公钥，签名格式假设不成立" >&2; exit 1; }
say "INFO 自检：site/public/appcast.xml 对 prototype/Info.plist 的 SUPublicEDKey 验签 OK（签名格式与本工具一致）"
read -r priv pub < <($sign keygen)
python3 -I - "$tmp/serve/appcast.xml" "$zip_url" <<'PY'
import re, sys, base64
dest, zip_url = sys.argv[1], sys.argv[2]
live = open('site/public/appcast.xml', encoding='utf-8').read()
body = live[:live.index('<!-- sparkle-signatures')]
draft = open('docs/releases/appcast-item-1.0.17.xml', encoding='utf-8').read()
item = re.search(r'<item>\s*<title>.*?</item>', draft, re.S).group(0)
item = item.replace('url="TODO-https://github.com/surfine/WindowShade/releases/download/v1.0.17/WindowShade-v1.0.17.zip"', 'url="%s"' % zip_url)
item = item.replace('length="TODO"', 'length="1"')
item = item.replace('sparkle:edSignature="TODO"', 'sparkle:edSignature="%s"' % base64.b64encode(bytes(64)).decode())
assert 'TODO' not in re.sub(r'<!--.*?-->|<description>.*?</description>', '', item, flags=re.S), 'unfilled TODO left in item'
i = body.index('<item>')
body = body[:i] + item.strip() + '\n    ' + body[i:]
open(dest, 'w', encoding='utf-8').write(body)
PY
sig=$($sign sign "$priv" "$tmp/serve/appcast.xml"); len=$(wc -c < "$tmp/serve/appcast.xml" | tr -d ' ')
printf '<!-- sparkle-signatures:\nedSignature: %s\nlength: %s\n-->\n' "$sig" "$len" >> "$tmp/serve/appcast.xml"
$sign verify "$pub" "$tmp/serve/appcast.xml" >/dev/null || { echo "本地清单自验签失败" >&2; exit 1; }
plutil -lint "$tmp/serve/appcast.xml" >/dev/null 2>&1 || xmllint --noout "$tmp/serve/appcast.xml" || { echo "本地清单不是合法 XML" >&2; exit 1; }
say "INFO 本地清单已生成并自验签（测试公钥 $pub，$len 字节）：$feed_url"

if [ "$dry" = 1 ]; then
  say "---- 计划 ----"
  say "1. ssh $host 先问 kern.hv_vmm_present，再读默认网关；宿主在 $gw:$port 起 python3 http.server（目录：临时目录，只含 appcast.xml）"
  say "2. 1.0.16：${app1016:-gh release download v1.0.16 --repo $repo -p '*.zip'} -> ditto -> 来宾 ~/Applications/wsqa-p3-1016"
  say "3. 1.0.17：$app1017 -> ditto -> 来宾 ~/Applications/wsqa-p3-1017"
  say "4. 来宾：prep（存偏好）-> run p3-1016（feed-via=$via，测试公钥）-> run p3-1017 -> cleanup（还原偏好、删 App）"
  say "5. 证据拷回 $out"
  say "---- 生成的清单（节选：新增条目与签名块）----"
  sed -n '/<item>/,/<\/item>/p' "$tmp/serve/appcast.xml" | sed -n '1,/<\/item>/p'
  tail -4 "$tmp/serve/appcast.xml"
  exit 0
fi

# --- 3. 备好两份 App ---
mkdir -p "$out"
zip_of() { # zip_of 路径 目标.zip
  case "$1" in
    *.zip) cp "$1" "$2" ;;
    *.app) ditto -c -k --keepParent "$1" "$2" ;;
    *) echo "不认识的包：$1（要 .app 或 .zip）" >&2; return 1 ;;
  esac
}
if [ -z "$app1016" ]; then
  say "INFO 取 1.0.16 发布包：gh release download v1.0.16 --repo $repo"
  gh release download v1.0.16 --repo "$repo" -p '*.zip' -D "$tmp/dl"
  app1016=$(ls "$tmp"/dl/*.zip | head -1)
fi
[ -e "$app1016" ] || { echo "找不到 1.0.16：$app1016" >&2; exit 1; }
[ -e "$app1017" ] || { echo "找不到 1.0.17 构建：$app1017（用 --app-1017 指定；duo-validation 里的构建可能不在这份 worktree 里）" >&2; exit 1; }
zip_of "$app1016" "$tmp/p3-1016.zip"; zip_of "$app1017" "$tmp/p3-1017.zip"

# --- 4. 起服务 ---
python3 -m http.server "$port" --bind "$gw" --directory "$tmp/serve" >"$tmp/http.log" 2>&1 &
http_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fs "$feed_url" -o /dev/null && break; sleep 0.5; done
curl -fs "$feed_url" -o /dev/null || { echo "本地服务没起来：$feed_url" >&2; exit 1; }
: > "$tmp/http.log"   # 自己的探测请求不算
g "curl -fs -m 5 '$feed_url' -o /dev/null" || { echo "来宾连不到 $feed_url（宿主防火墙或网桥地址不对）" >&2; exit 1; }
: > "$tmp/http.log"

# --- 5. 传进来宾并跑 ---
guest_touched=1
scp -q "${ssh_opts[@]}" "$tmp/p3-1016.zip" "$tmp/p3-1017.zip" tests/vm/updater-in-guest.sh "$host:/tmp/"
g "mkdir -p ~/Applications/wsqa-p3-1016 ~/Applications/wsqa-p3-1017 && ditto -x -k /tmp/p3-1016.zip ~/Applications/wsqa-p3-1016 && ditto -x -k /tmp/p3-1017.zip ~/Applications/wsqa-p3-1017 \
  && ls -d ~/Applications/wsqa-p3-1016/*.app ~/Applications/wsqa-p3-1017/*.app"
g "bash /tmp/updater-in-guest.sh prep"
run_one() { # run_one 标签 目录名
  local label=$1 dir=$2 app
  app=$(g "ls -d \$HOME/Applications/$dir/*.app | head -1")
  g "bash /tmp/updater-in-guest.sh run $label '$app' '$feed_url' '$pub' $via" | tee "$tmp/$label.guest.txt" | sed 's/^/  /'
}
run_one p3-1016 wsqa-p3-1016 || true
cp "$tmp/http.log" "$tmp/http-1016.log"; : > "$tmp/http.log"
run_one p3-1017 wsqa-p3-1017 || true
cp "$tmp/http.log" "$tmp/http-1017.log"

# --- 6. 取证据（清理在 trap 里） ---
scp -q -r "${ssh_opts[@]}" "$host:wsqa-p3/shots" "$host:wsqa-p3/ax" "$host:wsqa-p3/logs" "$out/" 2>/dev/null || echo "WARN 证据没完全拷回来"
cp "$tmp"/http-*.log "$tmp"/*.guest.txt "$out/" 2>/dev/null || true
cp "$tmp/serve/appcast.xml" "$out/local-appcast.xml"

# --- 7. 判读 ---
field() { sed -n "s/.*AXRESULT.* $2=\([^ ]*\).*/\1/p" "$1" | tail -1; }
fetched() { grep -q 'GET /appcast.xml' "$1"; }
zip_hit() { grep -q 'GET /WindowShade-v1.0.17.zip' "$1"; }
echo; echo "== Phase 3 判读（证据：$out）=="
# 1.0.16
f="$tmp/p3-1016.guest.txt"; cls=$(field "$f" class); drive=$(field "$f" drive); h="$tmp/http-1016.log"
if ! grep -q AXRESULT "$f" 2>/dev/null; then record "INCONCLUSIVE phase3/1.0.16 来宾没产出结果（见 $out/）"
elif ! fetched "$h"; then record "INCONCLUSIVE phase3/1.0.16 本地清单没被取到（更新器没启动，或 SUFeedURL 覆盖没生效；updater_started=$(field "$f" updater_started)；试 --feed-via plist）"
elif zip_hit "$h" || [ "$cls" = install ]; then record "FAIL phase3/1.0.16 出现了安装路径（class=$cls，zip 被请求=$(zip_hit "$h" && echo yes || echo no)）"
elif [ "$cls" = download ] && [ "$(field "$f" crash)" = no ]; then record "PASS phase3/1.0.16 弹出手动下载提示＋打开下载页，没有安装按钮，没请求 zip"
elif [ "$cls" = none ] && [ "$drive" = ok ]; then record "FAIL phase3/1.0.16 触发了检查但没有出现任何提示"
elif [ "$cls" = none ]; then record "INCONCLUSIVE phase3/1.0.16 驱动不了菜单（drive=$drive），也没有被动出现提示"
else record "FAIL phase3/1.0.16 提示不是预期的手动下载（class=$cls，看 $out/ax/p3-1016.txt）"; fi
# 1.0.17
f="$tmp/p3-1017.guest.txt"; cls=$(field "$f" class); drive=$(field "$f" drive); h="$tmp/http-1017.log"
if ! grep -q AXRESULT "$f" 2>/dev/null; then record "INCONCLUSIVE phase3/1.0.17 来宾没产出结果（见 $out/）"
else
  ver=$(field "$f" version); build=$(field "$f" build)
  if [ "${build:-0}" -lt 17 ] 2>/dev/null; then record "INCONCLUSIVE phase3/1.0.17 传进去的不是 1.0.17 构建（version=$ver build=$build；用 --app-1017 指向新构建）"
  elif ! fetched "$h"; then record "INCONCLUSIVE phase3/1.0.17 本地清单没被取到（updater_started=$(field "$f" updater_started)）"
  elif [ "$(field "$f" crash)" = yes ] || [ "$(field "$f" alive)" = no ]; then record "FAIL phase3/1.0.17 崩溃或退出（crash=$(field "$f" crash) alive=$(field "$f" alive)）"
  elif zip_hit "$h" || [ "$cls" = install ] || [ "$cls" = download ]; then record "FAIL phase3/1.0.17 在 1.0.17 上弹出了假更新（class=$cls）"
  elif [ "$cls" = uptodate ]; then record "PASS phase3/1.0.17 显示已是最新，没崩溃，没假版本"
  elif [ "$cls" = none ] && [ "$drive" = ok ]; then record "FAIL phase3/1.0.17 触发了检查但没有出现「已是最新」"
  elif [ "$cls" = none ]; then record "INCONCLUSIVE phase3/1.0.17 驱动不了菜单（drive=$drive）"
  else record "FAIL phase3/1.0.17 小窗内容不是「已是最新」（class=$cls，看 $out/ax/p3-1017.txt）"; fi
  case "$(field "$f" rollback)" in
    absent) record "PASS phase3/1.0.17 设置里没有「回到 …」" ;;
    present) record "FAIL phase3/1.0.17 设置里出现了「回到 …」" ;;
    *) record "INCONCLUSIVE phase3/1.0.17 没能看到设置里的更新分组（settings=$(field "$f" settings)）；回头人工看 $out/shots/p3-1017-settings.png" ;;
  esac
fi
printf '%s\n' "${verdicts[@]}" > "$out/verdicts.txt"
if printf '%s\n' "${verdicts[@]}" | grep -q '^FAIL'; then exit 1; fi
if printf '%s\n' "${verdicts[@]}" | grep -q '^INCONCLUSIVE'; then exit 4; fi
