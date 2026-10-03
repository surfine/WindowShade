#!/usr/bin/env python3
"""Conservative lexical diff guard, not taint analysis or a privacy certification."""
from pathlib import Path
from collections import Counter
import json,re,sys,argparse
p=argparse.ArgumentParser();p.add_argument('--repo',required=True,type=Path);a=p.parse_args()
r=json.loads((Path(__file__).resolve().parent/'registry.json').read_text())
if not (a.repo/'prototype').is_dir():sys.exit('FAIL missing prototype directory')
expected=Counter((s['path'],s['symbol'],s['source']) for s in r['sites']);actual=Counter()
for path in sorted((a.repo/'prototype').rglob('*.swift')):
    if any(x in path.parts for x in ('Vendor','.build','dist')):continue
    for line in path.read_text().splitlines():
        for m in re.finditer(r['scanner_pattern'],line):actual[(str(path.relative_to(a.repo)),m[0],line.strip())]+=1
added=actual-expected
for path,symbol,line in added:print(f'UNREGISTERED {path}: {symbol} | {line}')
if added:sys.exit(1)
print(f'PASS privacy-registry: {sum(actual.values())} lexical sites, no unregistered additions; removed={sum((expected-actual).values())}')
