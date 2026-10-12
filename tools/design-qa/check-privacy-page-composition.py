#!/usr/bin/env python3
import json,sys,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]);data=json.loads((out/'frames.json').read_text());registry=json.loads((root/'tools/privacy/registry.json').read_text())
rows=[s for s in registry['signals'] if s.get('status')!='planned' and not s.get('appearsWith')]
expected=[s['id'] for g in registry['groups'] for s in rows if s['group']==(g['title'] if isinstance(g,dict) else g)]
groups=[g['title'] if isinstance(g,dict) else g for g in registry['groups']]
assert data['candidateOnly'] and not data['pageInstantiated']
for key in ['sourcesRead','settingsWrites','globalInputEvents']:assert data[key]==0
assert len(data['frames'])==12
for f in data['frames']:
 assert f['groups']==groups,(f['name'],'groups')
 assert [r['id'] for r in f['rows']]==expected,(f['name'],'rows')
 assert not f['visible'] and f['alpha']==0 and f['actions']==0
 assert abs(f['pageWidth']-640)<.1
 assert 0<=f['scrollY']<=f['maxScrollY']+.1
 if f['position']=='top':assert f['scrollY']==0
 if f['position']=='bottom':assert abs(f['scrollY']-f['maxScrollY'])<.1
 previous=None
 for r in f['rows']:
  assert abs(r['width']-608)<.5,(f['name'],r['id'],r['width'])
  assert r['height']>20
  if previous is not None:assert r['y']>=previous-.5
  previous=r['y']+r['height']
  body=[x for x in r['fields'] if x['role']=='privacy-detail-body']
  assert bool(body)==f['expanded']
  for b in body:
   assert b['height']+1>=b['neededHeight'],(f['name'],r['id'],'height',b)
   assert b['x']>=0 and b['x']+b['width']<=r['width']+2.1
 for c in f['controls']:
  assert c['mockTarget'] and c['width']>=20 and c['height']>10
 if f['expanded']:
  known={'activities','calendar','downloads','login','autoUpdate','desktop','focusQuiet'}
  switches=[c['row'] for c in f['controls'] if c['kind']=='switch']
  assert switches==[r['id'] for g in groups for r in rows if r['group']==g and r.get('switch') in known]
 else:assert not any(c['kind']=='switch' for c in f['controls'])
 assert any(c['kind']=='grant' for c in f['controls'])
sources=json.loads((out/'sources.json').read_text());assert len(sources)==518
for rel,sha in sources.items():assert hashlib.sha256((root/rel).read_bytes()).hexdigest()==sha,rel
print('PASS 12 actual-component static composition frames; registry order, row geometry, mock controls, bounded scroll, current 518 inputs')
