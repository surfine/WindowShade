#!/usr/bin/env python3
"""Check pinned schema bytes and JSON pointers only. Does not connect to an agent or validate wire traffic."""
from pathlib import Path
import argparse,hashlib,json,sys
p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,required=True);a=p.parse_args()
b=Path(__file__).resolve().parent.parent;s=a.repo/'docs/handoff/reference/codex-app-server-schema-0.153.0'
hashes=json.loads((b/'validation/schema-input-sha256.json').read_text())
found={str(p.relative_to(s)):hashlib.sha256(p.read_bytes()).hexdigest() for p in s.rglob('*.json')}
if found!=hashes:sys.exit('STOP pinned schema file set or hash changed; main-model review required')
evidence=json.loads((b/'validation/schema-evidence.json').read_text())
for e in evidence:
 obj=json.loads((a.repo/e['file']).read_text())
 for key in e['pointer'].strip('/').split('/'):
  key=key.replace('~1','/').replace('~0','~');obj=obj[int(key)] if isinstance(obj,list) else obj[key]
 if obj!=e['value']:sys.exit('STOP schema pointer changed: '+e['pointer'])
print(f'PASS pinned-schema: {len(hashes)} files, {len(evidence)} pointers; no live protocol test')
