#!/usr/bin/env python3
"""Actual native privacy row geometry only; no live privacy assurance."""
import hashlib,json,math,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]);r=json.loads((out/'frames.json').read_text())
assert not r['pageInstantiated'] and r['plannedFixtureOnly']
assert all(r[k]==0 for k in ['sourcesRead','grantActions','exports','settingsWrites','globalInputEvents'])
samples=['battery','missing','denied','granted','long-value','expanded','technical','planned']
final='actualRowWidth' in r['frames'][0]
widths=[640,448,300] if final else [448,300]
assert len(r['frames'])==len(widths)*16
for parent in ['light','dark']:
 for width in widths:
  frames=[f for f in r['frames'] if f['name'].startswith(f'{parent}-{width}-')]
  assert [f['sample'] for f in frames]==samples
  for f in frames:
   name=f['name'];s=f['sample'];labels=f['labels']
   assert not f['visible'] and not f['active'] and f['alpha']==0 and f['mainThread'] and f['toggles']==0,name
   if final:assert abs(f['actualRowWidth']-width)<0.1 and abs(f['hostWidth']-(width+32))<0.1,name
   for l in labels:
    b=l['frame'];assert all(math.isfinite(v) for v in b.values()),name
    # AppKit text field control borders extend two points beyond text alignment rectangles.
    assert b['x']>=-2.1 and b['x']+b['width']<=width+2.1,(name,l['text'][:20],b)
    assert b['width']>0 and b['height']>0,name
    assert b['y']>=-2.1 and b['y']+b['height']<=f['height']+2.1,(name,l['text'][:20],b)
   title=labels[0];subtitle=labels[1];value=labels[2]
   if final:assert title['tooltip']==title['text'],name
   assert subtitle['tooltip']==subtitle['text'],name
   assert value['frame']['x']>=max(title['frame']['x']+title['frame']['width'],subtitle['frame']['x']+subtitle['frame']['width'])+5.5,name
   if s=='battery':assert value['text']=='妙控鼠标 82%',name
   if s=='missing':assert value['text']=='没读到',name
   if s=='denied':assert value['text']=='去授权' and not any(b['isGrant'] for b in f['buttons']),name
   if s in ['granted','expanded','technical']:assert value['text']=='已授权',name
   if s=='long-value':
    if final:assert value['breakMode']==5,name  # actual AppKit middle truncation retains suffix
    assert value['tooltip']==value['text'] and value['frame']['width']<=width*0.4+4.1,name
    assert value['naturalWidth']>value['frame']['width'],name
   if f['expanded']:
    for prefix in ['读到的：','为什么：','去了哪里：','什么时候读：','开关：','合起来能看出什么：']:
     assert any(l['text'].startswith(prefix) for l in labels),name
    assert all(l['wraps'] and l['maxLines']==0 for l in labels[3:]),name
   if s=='technical':assert any(l['text'].startswith('接口：') for l in labels),name
   if s=='planned':assert value['text']=='还没读' and f['registeredStatus']=='planned',name
renderer=json.loads((out/'renderer.json').read_text());assert renderer['swiftLanguageVersion']==6 and renderer['strictConcurrency'] and renderer['warningsAsErrors'] and not renderer['optimized']
sources=json.loads((out/'sources.json').read_text());assert len(sources)==518
for p,h in sources.items():assert hashlib.sha256((root/p).read_bytes()).hexdigest()==h,p
print(json.dumps({'status':'actual_row_static_pass','frames':len(r['frames']),'sources':518,'page/live values/actions/privacy network assurance':'not_run','motion/hardware/readscreen':'not_run'},ensure_ascii=False))
