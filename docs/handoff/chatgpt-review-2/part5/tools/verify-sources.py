#!/usr/bin/env python3
"""Check local code-map hashes; external URLs are evidence references, not network tests."""
from pathlib import Path
import argparse,hashlib,json,sys
p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);args=p.parse_args()
root=Path(__file__).resolve().parents[1]; errors=[]
for item in json.loads((root/'sources/code-map.json').read_text())['files']:
 rel=item['path']; path=root/rel if rel.startswith('overlay/') else args.base/rel
 if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:errors.append(rel)
print(json.dumps({'local_hashes_match':not errors,'mismatches':errors,'external_network_checked':False},indent=2))
sys.exit(1 if errors else 0)
