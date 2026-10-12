#!/usr/bin/env python3
"""Read actual production Row fixture output, not independent candidate JSON."""
import hashlib,json,math,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]);r=json.loads((out/'frames.json').read_text());registry=json.loads((root/'tools/privacy/registry.json').read_text())
signals={s['id']:s for s in registry['signals']}
assert not r['pageInstantiated'] and r['plannedFixtureOnly']
assert all(r[k]==0 for k in ['sourcesRead','grantActions','exports','settingsWrites','globalInputEvents'])
samples=['battery','missing','denied','granted','long-value','expanded','technical','planned']
assert len(r['frames'])==48
for parent in ['light','dark']:
 for width in [640,448,300]:
  batch=[f for f in r['frames'] if f['name'].startswith(f'{parent}-{width}-')];assert [f['sample'] for f in batch]==samples
  for f in batch:
   name=f['name'];sample=f['sample'];labels=f['labels'];src=signals[f['rowID']]
   assert not f['visible'] and not f['active'] and f['alpha']==0 and f['mainThread'] and f['toggles']==0,name
   assert abs(f['actualRowWidth']-width)<0.1 and abs(f['hostWidth']-(width+32))<0.1,name
   for field in labels:
    b=field['frame'];assert all(math.isfinite(v) for v in b.values()),name
    assert b['x']>=-2.1 and b['x']+b['width']<=width+2.1 and b['y']>=-2.1 and b['y']+b['height']<=f['height']+2.1,(name,field['text'][:18],b)
    assert not field['editable'] and b['height']>0,name
   title,subtitle,value=labels[:3]
   assert title['tooltip']==title['text'] and subtitle['tooltip']==subtitle['text'],name
   assert value['frame']['x']>=max(x['frame']['x']+x['frame']['width'] for x in [title,subtitle])+5.5,name
   if sample=='long-value':assert value['breakMode']==5 and value['tooltip']==value['text'] and value['frame']['width']<=width*0.4+4.1,name
   if sample=='missing':assert value['text']=='没读到',name
   if sample=='denied':assert value['text']=='去授权' and not any(b['isGrant'] for b in f['buttons']),name
   if sample in ['granted','expanded','technical']:assert value['text']=='已授权',name
   if sample=='planned':assert value['text']=='还没读' and f['registeredStatus']=='planned',name
   details=[x for x in labels if x['role'].startswith('privacy-detail-')]
   if not f['expanded']:assert not details,name;continue
   expected=[(key,src[column]) for key,column in [('读到的','reads'),('为什么','purpose'),('去了哪里','destination'),('什么时候读','activation'),('开关','toggle'),('合起来能看出什么','combined')] if src.get(column)]
   interfaces=sorted(set(s['symbol'] for s in registry['sites'] if s['signal']==f['rowID']))
   if sample=='technical' and interfaces:expected.append(('接口','、'.join(interfaces)))
   assert len(details)==len(expected)*2,name
   prev=None;expected_font=max(10,title['font']-1)
   for i,(key,text) in enumerate(expected):
    label,body=details[i*2:i*2+2]
    assert label['role']=='privacy-detail-label' and body['role']=='privacy-detail-body',name
    assert label['text']=={'什么时候读':'什么时候','合起来能看出什么':'合起来看'}.get(key,key) and label['tooltip']==key,name
    assert body['text']==text and body['tooltip']==text,name
    for field in [label,body]:
     assert field['font']==expected_font and field['wraps'] and field['maxLines']==0 and field['selectable'],name
     assert field['frame']['height']+1>=field['cellFittingHeight'],(name,key,'cell text clipped',field['frame'],field['cellFittingHeight'])
    a=label['frame'];b=body['frame'];assert abs(a['width']-(expected_font*4.4+4))<=0.5,name
    assert b['x']-(a['x']+a['width'])>=5.5,name
    assert abs(a['y']+a['height']-b['y']-b['height'])<0.1,name
    top=max(a['y']+a['height'],b['y']+b['height']);bottom=min(a['y'],b['y'])
    if prev is not None:assert prev-top>=3.9,name
    prev=bottom;assert body['color'][3]>label['color'][3],name
sources=json.loads((out/'sources.json').read_text());assert len(sources)==518
for p,h in sources.items():assert hashlib.sha256((root/p).read_bytes()).hexdigest()==h,p
renderer=json.loads((out/'renderer.json').read_text());assert renderer['swiftLanguageVersion']==6 and renderer['strictConcurrency'] and renderer['warningsAsErrors'] and not renderer['optimized']
print(json.dumps({'status':'production_row_static_pass','frames':48,'sources':518,'font':'actual body-1; one current system setting only','content':'exact registry; all actual cell fitting height contained','page/source/actions/VO/privacy/motion/hardware':'not_run'},ensure_ascii=False))
