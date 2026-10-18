#!/bin/bash
# 公证一个 Developer ID 签名的 WindowShade.app，把公证票据钉进包里，再用 Gatekeeper 核一遍。
# 用法：scripts/notarize.sh [WindowShade.app 路径]（默认 .build/release/WindowShade.app，即 build.sh --release 的产物）
# 凭证：钥匙串里的 notarytool 配置（默认名 windowshade-notary，用 WINDOWSHADE_NOTARY_PROFILE 改）。
#       由本人用 `xcrun notarytool store-credentials` 存一次；本脚本不读、不打印任何密码。
# 成功：退出 0，包已钉票据，`spctl` 认它是 Notarized Developer ID。之后再从这个包打发布 zip。
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-.build/release/WindowShade.app}"
PROFILE="${WINDOWSHADE_NOTARY_PROFILE:-windowshade-notary}"
[ -d "$APP" ] || { echo "ERROR: 找不到 $APP；先跑 cd prototype && ./build.sh --release" >&2; exit 1; }

authority=$(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
case "$authority" in
  "Developer ID Application:"*) ;;
  *) echo "ERROR: $APP 不是 Developer ID 签的（${authority}）；只有 --release 的产物能公证。" >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$APP"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
ditto -c -k --keepParent "$APP" "$work/submit.zip"
echo "==> 送公证（等 Apple 回复，通常几分钟）：$(basename "$APP")，$(du -h "$work/submit.zip" | cut -f1)"
xcrun notarytool submit "$work/submit.zip" --keychain-profile "$PROFILE" --wait --output-format json > "$work/result.json"
id=$(plutil -extract id raw -o - "$work/result.json")
status=$(plutil -extract status raw -o - "$work/result.json")
echo "==> 公证结果：${status}（submission $id）"
if [ "$status" != "Accepted" ]; then
  xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
assessment=$(spctl --assess --type execute -vv "$APP" 2>&1)
echo "$assessment" | sed 's/^/    /'
echo "$assessment" | grep -q 'source=Notarized Developer ID' || { echo "ERROR: Gatekeeper 没认出公证" >&2; exit 1; }
echo "PASS notarize: 已公证、已钉票据，Gatekeeper 认作 Notarized Developer ID"
