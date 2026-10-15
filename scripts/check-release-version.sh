#!/bin/bash
# 版本号纪律（规格 R34）：一个 build 号只对应一份构建。
# 发布前、写 appcast 之前跑：prototype/Info.plist 的 CFBundleVersion 必须大于
# site/public/appcast.xml 里已发过的每一个 sparkle:version，否则非零退出。
# 重发（哪怕只改了文案）也要升 CFBundleVersion：同号重发时，已装的人收不到更新提示。
set -euo pipefail
cd "$(dirname "$0")/.."
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" prototype/Info.plist)
case "$build" in ''|*[!0-9]*) echo "FAIL release-version: CFBundleVersion「$build」不是正整数" >&2; exit 1;; esac
shipped=$(grep -oE '<sparkle:version>[0-9]+' site/public/appcast.xml | grep -oE '[0-9]+$' | sort -n | tail -1 || true)
if [ -n "$shipped" ] && [ "$build" -le "$shipped" ]; then
  echo "FAIL release-version: CFBundleVersion=$build，appcast 里已发过 $shipped。先在 prototype/Info.plist 升 CFBundleVersion。" >&2
  exit 1
fi
echo "PASS release-version: CFBundleVersion=$build（appcast 最高 ${shipped:-无}）"
