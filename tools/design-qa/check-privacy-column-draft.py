#!/usr/bin/env python3
"""Actual native draft output, original registry text and layout; no product acceptance."""
import hashlib,json,math,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2];work=Path(sys.argv[1]);r=json.loads((work/'final/frames.json').read_text())
registry=json.loads((root/'tools/privacy/registry.json').read_text());signals={x['id']:x for x in registry['signals']}
keys=[('读到的','reads'),('为什么','purpose'),('去了哪里','destination'),('什么时候读','activation'),('开关','toggle'),('合起来能看出什么','combined')]
assert r['candidateOnly'] and not r['productionIntegration'] and r['plannedFixtureOnly']
assert all(r[k]==0 for k in ['realSources','actions','networkReads','globalInputEvents','preferencesWrites'])
assert len(r['frames'])==36
for parent in ['light','dark']:
 for width in [640,448,300]:
  for id in ['window-ax','battery','face-identity']:
   for technical in [False,True]:
    name=f"{parent}-{width}-{id}-{'technical' if technical else 'plain'}"
    f=next(x for x in r['frames'] if x['name']==name);source=signals[id]
    assert f['width']==width and abs(f['actualWidth']-width)<0.1 and f['status']==source['status'],name
    assert not f['visible'] and not f['active'] and f['alpha']==0 and f['mainThread'],name
    assert abs(f['hostSize']['width']-(width+32))<0.1 and abs(f['hostSize']['height']-(f['height']+32))<0.1,name
    interfaces=sorted(set(s['symbol'] for s in registry['sites'] if s['signal']==id));assert f['interfaces']==interfaces,name
    expect=[(k,source[v]) for k,v in keys if source.get(v)]
    if technical and interfaces:expect.append(('接口','、'.join(interfaces)))
    assert len(f['fields'])==len(expect)*2,name
    previous_bottom=None
    for i,(key,text) in enumerate(expect):
     label,body=f['fields'][i*2:i*2+2]
     assert label['role']=='label' and body['role']=='body' and label['key']==body['key']==key,name
     assert body['text']==text and body['tooltip']==text,name
     assert label['text']=={'什么时候读':'什么时候','合起来能看出什么':'合起来看'}.get(key,key) and label['tooltip']==key,name
     for field in [label,body]:
      b=field['frame'];assert field['font']==12 and field['wraps'] and field['maxLines']==0 and not field['editable'],name
      assert all(math.isfinite(v) for v in b.values()),name
      assert b['x']>=-2.1 and b['x']+b['width']<=width+2.1 and b['y']>=-0.1 and b['y']+b['height']<=f['height']+0.1 and b['height']>0,(name,key,b)
     a=label['frame'];b=body['frame'];assert abs(a['width']-(12*4.4+4))<=0.5,name
     assert b['x']-(a['x']+a['width'])>=5.5,name # control borders extend two points around glyph alignment
     top=max(a['y']+a['height'],b['y']+b['height']);bottom=min(a['y'],b['y'])
     assert abs((a['y']+a['height'])-(b['y']+b['height']))<0.1,name
     assert a['height']<=15.1,name # shortened visible label stays one line at original4.4em
     if previous_bottom is not None:assert previous_bottom-top>=3.9,name
     previous_bottom=bottom
     assert body['color'][3]>label['color'][3],name
for path,digest in json.loads((work/'sources.json').read_text()).items():assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest,path
renderer=json.loads((work/'renderer.json').read_text());assert renderer['swiftLanguageVersion']==6 and renderer['strictConcurrency'] and renderer['warningsAsErrors'] and renderer['cocoaOnly']
assert hashlib.sha256((work/'draft').read_bytes()).hexdigest()==renderer['sha256']
print(json.dumps({'status':'candidate_static_pass','frames':36,'registry_text':'exact including real site interface aggregation','font':12,'label_column':'4.4em; four-character visible aliases, full tooltip','product/source/actions/readscreen/motion/hardware':'not_run'},ensure_ascii=False))
