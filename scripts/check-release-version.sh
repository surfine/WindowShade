#!/bin/bash
# 版本号纪律（规格 R34）：一个 build 号只对应一份构建。
# 发布前、写 appcast 之前跑：prototype/Info.plist 的 CFBundleVersion 必须大于
# site/public/appcast.xml 里已发过的每一个 sparkle:version，否则非零退出。
# 重发（哪怕只改了文案）也要升 CFBundleVersion：同号重发时，已装的人收不到更新提示。
set -euo pipefail
cd "$(dirname "$0")/.."
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" prototype/Info.plist)
# build 号只用「数字与点」（2026-11-10 起；点号是 Sparkle 认的，连字号不认，见 scripts/build-version-compare.py 的说明）。
python3 -I scripts/build-version-compare.py "$build" "$build" >/dev/null \
  || { echo "FAIL release-version: CFBundleVersion「${build}」不是「数字与点」（例如 20261110.01）" >&2; exit 1; }
# Intel 实验版有自己的清单（site/public/appcast-intel.xml，从 1.0.21 起）；两份清单共用一个 build 号序列，取两份里最大的。
# 占位条目（enclosure 的 url 以 TODO 开头，发布日才填）不算「已发过」。
feeds=(site/public/appcast.xml)
[ -f site/public/appcast-intel.xml ] && feeds+=(site/public/appcast-intel.xml)
shipped=$(python3 -I - "${feeds[@]}" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
for feed in sys.argv[1:]:
    for it in ET.parse(feed).getroot().iter('item'):
        enc = it.find('enclosure')
        if enc is not None and (enc.get('url') or '').startswith('TODO'):
            continue
        v = (it.findtext('s:version', '', ns) or '').strip()
        if v:
            print(v)
PY
)
# 取两份清单里最大的那个：比较规则和 Sparkle 一致（见 scripts/build-version-compare.py）。
[ -n "$shipped" ] && shipped=$(python3 -I scripts/build-version-compare.py --max $shipped)
if [ -n "$shipped" ]; then
  newer=$(python3 -I scripts/build-version-compare.py "$build" "$shipped")
  if [ "$newer" != "1" ]; then
    echo "FAIL release-version: CFBundleVersion=${build}，appcast 里已发过 ${shipped}。先在 prototype/Info.plist 升 CFBundleVersion。" >&2
    exit 1
  fi
fi
echo "PASS release-version: CFBundleVersion=${build}（appcast 最高 ${shipped:-无}）"
