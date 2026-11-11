#!/bin/bash
# 核对发布 zip 里的 CFBundleVersion 与源码树的 prototype/Info.plist 一致（只读 zip，不解压到磁盘）。
# 发布关之前用：zip 由 DEVELOPMENT.md 发布流程里单独的公证、打包步骤产出，同名的旧 zip 会让后面的门禁照样通过。
# 用法：scripts/check-zip-build.sh <zip> [期望的 CFBundleVersion]
# 退出码：0 一致；1 zip 缺失、读不出或版本不同。
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
zip="${1:?用法：check-zip-build.sh <zip> [期望的 CFBundleVersion]}"
expected="${2:-$(plutil -extract CFBundleVersion raw -o - "$ROOT/prototype/Info.plist")}"

if [ ! -f "$zip" ]; then
  echo "FAIL 缺少 $zip：还没有打这个包。按 docs/DEVELOPMENT.md 发布流程先公证、再 ditto -c -k --keepParent 打 zip。" >&2
  exit 1
fi
actual="$(unzip -p "$zip" 'WindowShade.app/Contents/Info.plist' 2>/dev/null | plutil -extract CFBundleVersion raw -o - - 2>/dev/null)"
if [ -z "$actual" ]; then
  echo "FAIL 读不出 $zip 里的 WindowShade.app/Contents/Info.plist（zip 损坏，或 .app 不在顶层）。重新按 docs/DEVELOPMENT.md 发布流程打包。" >&2
  exit 1
fi
if [ "$actual" != "$expected" ]; then
  echo "FAIL $zip 过期：包里 CFBundleVersion=$actual，源码树 prototype/Info.plist 是 $expected。" >&2
  echo "  这个 zip 不是本次 --release 构建的产物。按 docs/DEVELOPMENT.md 发布流程对新构建重新公证、再 ditto -c -k --keepParent 覆盖它。" >&2
  exit 1
fi
echo "ok $zip：CFBundleVersion=$actual 与 prototype/Info.plist 一致"
