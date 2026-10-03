#!/usr/bin/env python3
"""Conservative lexical diff guard, not taint analysis or a privacy certification."""
from pathlib import Path
from collections import Counter
import json,re,sys,argparse
p=argparse.ArgumentParser();p.add_argument('--repo',required=True,type=Path);a=p.parse_args()
r=json.loads((Path(__file__).resolve().parent/'registry.json').read_text())
if not (a.repo/'prototype').is_dir():sys.exit('FAIL missing prototype directory')
# 隐私页的数据源是从这张登记表生成的镜像：里面必然出现接口名（那是给人看的说明），
# 不是新的读取点，扫它等于自己查自己。只跳过带生成标记的文件，手写文件照常扫。
GENERATED_MARKER='tools/privacy/make-privacy-page-source.py'
expected=Counter((s['path'],s['symbol'],s['source']) for s in r['sites']);actual=Counter()
for path in sorted((a.repo/'prototype').rglob('*.swift')):
    if any(x in path.parts for x in ('Vendor','.build','dist')):continue
    lines=path.read_text().splitlines()
    if lines and GENERATED_MARKER in lines[0]:continue
    for line in lines:
        for m in re.finditer(r['scanner_pattern'],line):actual[(str(path.relative_to(a.repo)),m[0],line.strip())]+=1
added=actual-expected
for path,symbol,line in added:print(f'UNREGISTERED {path}: {symbol} | {line}')
if added:sys.exit(1)
print(f'PASS privacy-registry: {sum(actual.values())} lexical sites, no unregistered additions; removed={sum((expected-actual).values())}')
