#!/bin/bash
# 发布关（DEVELOPMENT.md「发布流程」第 4 步）：检查要发出去的那个 zip，不是构建目录。有一项不过就非零退出。
# 用法：
#   scripts/release-gate.sh <新版 zip> [--previous <上一版 zip 或 .app>] [--appcast <清单>] [--cert-change <Team ID>]
#   --previous 不给时用 gh 下载最新 release 的 zip（要联网、要 gh 已登录）。
#   --appcast 默认 site/public/appcast.xml；清单里要已经有这一版的条目（先写好清单再过关，再上传）。
#   --cert-change <Team ID>：换证书的那一版（docs/update.md）。第 3 步不比「DR 与上一版逐字相同」，改核
#   「Developer ID 签名、Team 是这个」；清单那一项还要是 informationalUpdate。
# 第 11 项卡顿账只打印 INFO，不影响退出码。
# 只读：不改清单、不上传、不碰日常运行的 App；会短暂运行新旧两版的 --self-check（无界面、约 1 秒）。
set -euo pipefail
cd "$(dirname "$0")/.."
ZIP=""; PREV=""; APPCAST="site/public/appcast.xml"; CERT_TEAM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --previous) PREV="$2"; shift 2 ;;
    --appcast) APPCAST="$2"; shift 2 ;;
    --cert-change) CERT_TEAM="$2"; shift 2 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) ZIP="$1"; shift ;;
  esac
done
[ -f "$ZIP" ] || { echo "usage: release-gate.sh <新版 zip> [--previous …] [--appcast …] [--cert-change <Team>]" >&2; exit 2; }
EXPECTED_FEED="https://windowshade.aaronlau.me/appcast.xml"
EXPECTED_ED_KEY="D/MZytH+oxawqKQsskoXBdwbvoPentrqfaj7Tj2pnkw="

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
plist() { /usr/libexec/PlistBuddy -c "Print $2" "$1/Contents/Info.plist" 2>/dev/null || true; }

# 1. 上一版
if [ -z "$PREV" ]; then
  tag=$(gh release list --limit 1 --json tagName -q '.[0].tagName')
  gh release download "$tag" -p '*.zip' -D "$work/prev-dl" >/dev/null
  PREV=$(ls "$work"/prev-dl/*.zip | grep -v sha256 | head -1)
fi
if [ -d "$PREV" ]; then PREV_APP="$PREV"; else
  mkdir -p "$work/prev"; ditto -x -k "$PREV" "$work/prev"; PREV_APP=$(ls -d "$work"/prev/*.app | head -1); fi
PREV_DR=$(codesign -d -r- "$PREV_APP" 2>&1 | sed -n 's/^designated => //p')
[ -n "$PREV_DR" ] && pass "1 上一版：$(plist "$PREV_APP" CFBundleShortVersionString)（build $(plist "$PREV_APP" CFBundleVersion)）" \
  || fail "1 读不到上一版的 DR：$PREV_APP"

# 2. 新 zip 里只有一个 WindowShade.app，签名完整
mkdir -p "$work/new"; ditto -x -k "$ZIP" "$work/new"
apps=$(find "$work/new" -maxdepth 1 -name '*.app' | wc -l | tr -d ' ')
APP="$work/new/WindowShade.app"
if [ "$apps" = "1" ] && [ -d "$APP" ] && codesign --verify --deep --strict "$APP" 2>/dev/null; then
  pass "2 zip 里只有一个 WindowShade.app，codesign --deep --strict 通过"
else fail "2 zip 内容或签名不对（.app 个数 $apps）"; fi
BUILD=$(plist "$APP" CFBundleVersion); VERSION=$(plist "$APP" CFBundleShortVersionString)
TEAM=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
AUTH=$(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)

# 3. DR 连续（换证书那一版改核 Developer ID 与 Team）
if [ -n "$CERT_TEAM" ]; then
  [[ "$AUTH" == "Developer ID Application:"* && "$TEAM" == "$CERT_TEAM" ]] \
    && pass "3 换证书的一版：$AUTH，Team $TEAM" || fail "3 换证书的一版要 Developer ID、Team $CERT_TEAM，实际 $AUTH / $TEAM"
else
  codesign --verify -R="$PREV_DR" "$APP" 2>/dev/null && pass "3 新版满足上一版的 DR" \
    || fail "3 新版不满足上一版的 DR（换证书要加 --cert-change <Team>，见 docs/update.md）"
fi

# 4. --self-check 返回 0 且带这次的 build 号
if out=$(perl -e 'alarm 5; exec @ARGV' "$APP/Contents/MacOS/WindowShade" --self-check 2>&1) && [[ "$out" == *"build=$BUILD"* ]]; then
  pass "4 --self-check：$out"; else fail "4 --self-check 没返回 0 或没有 build=$BUILD：${out:-无输出}"; fi

# 5. build 号比上一版大，也比清单里已发过的大
PREV_BUILD=$(plist "$PREV_APP" CFBundleVersion)
[ "$BUILD" -gt "$PREV_BUILD" ] 2>/dev/null && pass "5 build $BUILD > 上一版 $PREV_BUILD" || fail "5 build $BUILD 不大于上一版 $PREV_BUILD"

# 6–7、清单：这一版的条目、最低系统、架构、包大小、换证书标记
item=$(python3 -I - "$APPCAST" "$BUILD" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
root = ET.parse(sys.argv[1]).getroot()
for it in root.iter('item'):
    if (it.findtext('s:version', namespaces=ns) or '').strip() == sys.argv[2]:
        enc = it.find('enclosure')
        print('|'.join([it.findtext('s:minimumSystemVersion', '', ns).strip(),
                        it.findtext('s:hardwareRequirements', '', ns).strip(),
                        (enc.get('length') if enc is not None else ''),
                        'informational' if it.find('s:informationalUpdate', ns) is not None else '']))
        break
PY
)
if [ -z "$item" ]; then
  fail "6 清单 $APPCAST 里还没有 build $BUILD 的条目（先写好清单再过关）"
else
  IFS='|' read -r c_min c_hw c_len c_info <<< "$item"
  norm() { python3 -c 'import sys; p=[int(x) for x in sys.argv[1].split(".")]; p+= [0]*(3-len(p)); print(".".join(map(str,p[:3])))' "$1"; }
  [ "$(norm "$(plist "$APP" LSMinimumSystemVersion)")" = "$(norm "$c_min")" ] \
    && pass "6 LSMinimumSystemVersion 与清单 minimumSystemVersion 一致（$c_min）" \
    || fail "6 LSMinimumSystemVersion $(plist "$APP" LSMinimumSystemVersion) ≠ 清单 $c_min"
  archs=$(lipo -archs "$APP/Contents/MacOS/WindowShade")
  [ "$archs" = "$c_hw" ] && pass "7 架构 $archs 与清单 hardwareRequirements 一致" || fail "7 架构 $archs ≠ 清单 $c_hw"
  size=$(stat -f %z "$ZIP")
  [ "$size" = "$c_len" ] && pass "7b 清单里的包大小 $c_len 就是这个 zip" || fail "7b 清单里的包大小 $c_len ≠ zip $size（换包后要重签清单）"
  if [ -n "$CERT_TEAM" ]; then
    [ "$c_info" = "informational" ] && pass "7c 换证书的一版在清单里是 informationalUpdate" \
      || fail "7c 换证书的一版要在清单里标 sparkle:informationalUpdate（docs/update.md）"
  fi
fi

# 8. Sparkle、更新地址与公钥、看护同 Team
otool -L "$APP/Contents/MacOS/WindowShade" | grep -q '@rpath/Sparkle.framework' && [ "$(plist "$APP" SUPublicEDKey)" = "$EXPECTED_ED_KEY" ] \
  && [ "$(plist "$APP" SUFeedURL)" = "$EXPECTED_FEED" ] && pass "8 链接了 Sparkle，SUFeedURL 与 SUPublicEDKey 没变" \
  || fail "8 Sparkle 没链接，或 SUFeedURL / SUPublicEDKey 变了"
GUARD="$APP/Contents/Helpers/WindowShadeUpdateGuard.app"
[ -d "$GUARD" ] && [ "$(codesign -dv "$GUARD" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "$TEAM" ] \
  && pass "8b 看护在、签名同 Team（$TEAM）" || fail "8b 看护不在或 Team 不同"

# 9. 上一版读得懂这一版写的状态
state="$work/state"; mkdir -p "$state"
if [ "$PREV_BUILD" -lt 16 ] 2>/dev/null; then
  # 16 以前没有更新器、也不认 --read-state：拿它跑会整个 App 起来。文档规定这一步从第二个带更新器的版本起做。
  echo "SKIP 9 上一版 build $PREV_BUILD 不带更新器，没有 --read-state（DEVELOPMENT.md：第一个带更新器的版本跳过）"
elif "$APP/Contents/MacOS/WindowShade" --self-check --write-sample-state "$state" >/dev/null 2>&1 \
  && perl -e 'alarm 5; exec @ARGV' "$PREV_APP/Contents/MacOS/WindowShade" --self-check --read-state "$state" >/dev/null 2>&1; then
  pass "9 上一版读得懂这一版写的状态"; else fail "9 上一版读不懂这一版写的状态（或上一版不支持 --read-state）"; fi

# 10. 公证（Developer ID 的包必须已公证、已钉票据）
if [[ "$AUTH" == "Developer ID Application:"* ]]; then
  if xcrun stapler validate "$APP" >/dev/null 2>&1 && spctl --assess --type execute -vv "$APP" 2>&1 | grep -q 'source=Notarized Developer ID'; then
    pass "10 已公证、已钉票据，Gatekeeper 认作 Notarized Developer ID"
  else fail "10 Developer ID 的包没有公证或没钉票据（scripts/notarize.sh）"; fi
else
  fail "10 不是 Developer ID 签的（$AUTH）：2026-10-16 起发布包要 build.sh --release ＋ scripts/notarize.sh"
fi

# 11. 卡顿账（只报不挡：INFO，不计入 PASS／FAIL）。scripts/perf-report.sh 按 build 号记账，取这个候选 build 最近的一行。
ledger=docs/perf-ledger.md
perf_row=$([ -f "$ledger" ] && grep -F "(build $BUILD)" "$ledger" | tail -1 || true)
if [ -n "$perf_row" ]; then echo "INFO 11 卡顿账（build $BUILD，只报不挡）：${perf_row#| }"
else echo "INFO 11 卡顿账里还没有 build $BUILD 的行（scripts/perf-report.sh --host 或 --vm，只报不挡）"; fi

echo "== 发布关：$VERSION（build $BUILD）$([ $fails = 0 ] && echo '全部通过' || echo "$fails 项不过")"
[ "$fails" = 0 ]
