#!/bin/bash
# 版本号纪律（规格 R34）：一个 build 号只对应一份构建。
# 发布前、写 appcast 之前跑：prototype/Info.plist 的 CFBundleVersion 必须大于
# site/public/appcast.xml 里已发过的每一个 sparkle:version，否则非零退出。
# 重发（哪怕只改了文案）也要升 CFBundleVersion：同号重发时，已装的人收不到更新提示。
set -euo pipefail
cd "$(dirname "$0")/.."
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" prototype/Info.plist)
case "$build" in ''|*[!0-9]*) echo "FAIL release-version: CFBundleVersion「${build}」不是正整数" >&2; exit 1;; esac
# Intel 实验版有自己的清单（site/public/appcast-intel.xml，从 1.0.21 起）；两份清单共用一个 build 号序列，取两份里最大的。
# 占位条目（enclosure 的 url 以 TODO 开头，发布日才填）不算「已发过」。
feeds=(site/public/appcast.xml)
[ -f site/public/appcast-intel.xml ] && feeds+=(site/public/appcast-intel.xml)
shipped=$(python3 -I - "${feeds[@]}" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
vs = []
for feed in sys.argv[1:]:
    for it in ET.parse(feed).getroot().iter('item'):
        enc = it.find('enclosure')
        if enc is not None and (enc.get('url') or '').startswith('TODO'):
            continue
        v = (it.findtext('s:version', '', ns) or '').strip()
        if v.isdigit():
            vs.append(int(v))
print(max(vs) if vs else '')
PY
)
if [ -n "$shipped" ] && [ "$build" -le "$shipped" ]; then
  echo "FAIL release-version: CFBundleVersion=${build}，appcast 里已发过 ${shipped}。先在 prototype/Info.plist 升 CFBundleVersion。" >&2
  exit 1
fi
echo "PASS release-version: CFBundleVersion=${build}（appcast 最高 ${shipped:-无}）"
