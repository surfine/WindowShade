#!/bin/bash
# 给首次安装做 DMG：已公证、已钉票据的 WindowShade.app + 「应用程序」快捷方式 + 背景图。
# Sparkle 更新照旧用 zip（docs/update.md）；DMG 只放在 Release 页给第一次下载的人。
# 用法：scripts/make-dmg.sh [WindowShade.app 路径] [输出 .dmg 路径] [--capture-template]
#   默认 app = .build/release/WindowShade.app（先跑 build.sh --release ＋ scripts/notarize.sh）；
#   默认输出 = prototype/dist/WindowShade-v<版本>.dmg。
#   凭证：Developer ID 证书在钥匙串里；公证用 notarytool 配置 windowshade-notary（WINDOWSHADE_NOTARY_PROFILE 可改），不读、不打印密码。
#   WINDOWSHADE_SIGN_IDENTITY 可指定证书全名；不给就取钥匙串里唯一的 Developer ID Application。
# 版面：assets/dmg/background.png（@2x 可选）是背景图；图标位置存在 assets/dmg/DS_Store（模板）。
#   有模板就直接用，全程无界面。没有模板时只做出「能用但没排版」的 DMG，并提示：
#   在能开 Finder 的 Mac 上跑一次 `scripts/make-dmg.sh --capture-template`（会短暂弹出 Finder 窗口排版，
#   再把生成的 assets/dmg/DS_Store 提交）。排版要的是 Finder 自动化授权，所以放在人眼前做，不放进无人值守的发布流程。
# 成功：退出 0，DMG 已签名、已公证、已钉票据，spctl 认作 Notarized Developer ID。
set -euo pipefail
cd "$(dirname "$0")/.."
APP=""; OUT=""; CAPTURE=0
for a in "$@"; do
  case "$a" in
    --capture-template) CAPTURE=1 ;;
    -*) echo "unknown option $a" >&2; exit 2 ;;
    *) if [ -z "$APP" ]; then APP="$a"; else OUT="$a"; fi ;;
  esac
done
APP="${APP:-.build/release/WindowShade.app}"
PROFILE="${WINDOWSHADE_NOTARY_PROFILE:-windowshade-notary}"
VOLNAME="WindowShade"
[ -d "$APP" ] || { echo "ERROR: 找不到 $APP；先跑 cd prototype && ./build.sh --release 和 scripts/notarize.sh" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="${OUT:-prototype/dist/WindowShade-v${VERSION}.dmg}"

authority=$(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
case "$authority" in
  "Developer ID Application:"*) ;;
  *) echo "ERROR: $APP 不是 Developer ID 签的（$authority）。" >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP" >/dev/null || { echo "ERROR: $APP 没钉公证票据；先跑 scripts/notarize.sh" >&2; exit 1; }

IDENTITY="${WINDOWSHADE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  ids=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | sort -u)
  [ "$(printf '%s\n' "$ids" | grep -c .)" = "1" ] || { echo "ERROR: 钥匙串里的 Developer ID Application 证书不是恰好一张（${ids:-无}）；用 WINDOWSHADE_SIGN_IDENTITY 指定。" >&2; exit 1; }
  IDENTITY="$ids"
fi

work=$(mktemp -d); trap 'hdiutil detach "$work/mnt" -force >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
stage="$work/stage"; mkdir -p "$stage/.background" "$work/mnt"
ditto "$APP" "$stage/WindowShade.app"          # ditto 保留框架里的符号链接和票据
ln -s /Applications "$stage/Applications"
BG=assets/dmg/background.png
if [ -f assets/dmg/background@2x.png ]; then
  tiffutil -cathidpicheck "$BG" assets/dmg/background@2x.png -out "$stage/.background/background.tiff" >/dev/null
  BGNAME=background.tiff
else cp "$BG" "$stage/.background/background.png"; BGNAME=background.png; fi
chflags hidden "$stage/.background"
TEMPLATE=assets/dmg/DS_Store
[ "$CAPTURE" = 1 ] || { [ -f "$TEMPLATE" ] && cp "$TEMPLATE" "$stage/.DS_Store" || echo "NOTE: 没有 $TEMPLATE，DMG 不带图标排版；见本脚本头部说明。" >&2; }

mkdir -p "$(dirname "$OUT")"; rm -f "$OUT"
if [ "$CAPTURE" = 1 ]; then
  # 可写镜像 -> 挂载 -> 让 Finder 排版 -> 取回 .DS_Store。需要 Finder 自动化授权，只在人眼前跑。
  hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$work/rw.dmg"
  hdiutil attach -quiet -nobrowse -noverify -mountpoint "$work/mnt" "$work/rw.dmg"
  osascript <<OSA
tell application "Finder"
  set d to POSIX file "$work/mnt" as alias
  open d
  delay 1
  set w to container window of d
  set current view of w to icon view
  set toolbar visible of w to false
  set statusbar visible of w to false
  set the bounds of w to {200, 120, 860, 520}
  set opts to the icon view options of w
  set arrangement of opts to not arranged
  set icon size of opts to 128
  set text size of opts to 13
  set background picture of opts to POSIX file "$work/mnt/.background/$BGNAME"
  set position of item "WindowShade.app" of d to {170, 190}
  set position of item "Applications" of d to {490, 190}
  update d without registering applications
  delay 2
  close w
end tell
OSA
  sync; sleep 2
  cp "$work/mnt/.DS_Store" "$TEMPLATE"
  hdiutil detach -quiet "$work/mnt"
  echo "PASS 已写入 $TEMPLATE；检查后提交，再不带 --capture-template 重跑一次。"
  exit 0
fi

hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT"
codesign --force -s "$IDENTITY" --timestamp "$OUT"
codesign --verify --strict "$OUT"

echo "==> 送公证：$(basename "$OUT")，$(du -h "$OUT" | cut -f1)"
xcrun notarytool submit "$OUT" --keychain-profile "$PROFILE" --wait --output-format json > "$work/result.json"
id=$(plutil -extract id raw -o - "$work/result.json"); status=$(plutil -extract status raw -o - "$work/result.json")
echo "==> 公证结果：$status（submission $id）"
if [ "$status" != "Accepted" ]; then xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true; exit 1; fi
xcrun stapler staple "$OUT"
xcrun stapler validate "$OUT"
assessment=$(spctl -a -t open --context context:primary-signature -vv "$OUT" 2>&1)
echo "$assessment" | sed 's/^/    /'
echo "$assessment" | grep -q 'source=Notarized Developer ID' || { echo "ERROR: Gatekeeper 没认出 DMG 的公证" >&2; exit 1; }
(cd "$(dirname "$OUT")" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256")
echo "PASS make-dmg: $OUT 已签名、已公证、已钉票据（SHA-256 在 $OUT.sha256）"
