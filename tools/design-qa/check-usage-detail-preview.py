#!/usr/bin/env python3
"""Consume actual AppKit candidate outputs; no product integration acceptance."""
import hashlib,json,math,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1])
r=json.loads((out/'frames.json').read_text())
assert r['candidateOnly'] and not r['productionIntegration'] and not r['contextSourceQualified']
assert all(r[k]==0 for k in ['sourceControllers','actions','networkReads','globalInputEvents'])
samples=['normal','unknown','context-only','expired','long-model','unknown-window','zero','shared']
assert len(r['frames'])==16
for parent in ['light','dark']:
    fs=[f for f in r['frames'] if f['name'].startswith(parent+'-')]
    assert [f['sample'] for f in fs]==samples
    for f in fs:
        name=f['name'];s=f['sample'];fields={v['id']:v for v in f['fields']};w=f['windows'];page=f['pageSize']
        assert not f['visible'] and not f['active'] and f['alpha']==0 and f['mainThread'] and f['completions']==1,name
        assert page['width']==520 and 68<=page['height']<=480,name
        for v in fields.values():
            b=v['frame'];assert all(math.isfinite(x) for x in b.values()),name
            assert b['x']>=0 and b['y']>=0 and b['x']+b['width']<=520 and b['y']+b['height']<=page['height']+0.1,(name,v['id'],b)
            assert v['dark'] and v['tooltip']==v['text'],(name,v['id'])
        expected=[] if s in ['unknown','context-only','shared'] else [5,40] if s=='expired' else [88] if s=='unknown-window' else [0] if s=='zero' else [95,7]
        assert [v['leftPercent'] for v in w]==expected,name
        if len(w)==2:
            assert [v['name'] for v in w]==['五小时额度','七天额度'],name
            assert [v['windowMinutes'] for v in w]==[300,10080],name
        for i,v in enumerate(w):
            assert fields[f'window-{i}-amount']['text']==f"剩 {v['leftPercent']}%",name
            assert fields[f'window-{i}-amount']['font']==22,name
            if v['recovery'] is not None:assert fields[f'window-{i}-recovery']['text']==v['recovery'],name
        if s=='expired':assert w[0]['recovery']=='等待用量更新',name
        if s=='unknown-window':assert w[0]['name']=='账户额度' and w[0]['recovery'] is None,name
        if s=='shared':
            assert 'model' not in fields and 'context' not in fields and fields['project']['text']=='编程会话',name
            assert fields['account-empty']['text']=='用量已隐藏',name
        else:
            m=fields['model'];assert m['renderer']=='TextKit' and m['maximumNumberOfLines']==2 and not m['editable'] and not m['selectable'],name
            assert m['truncated']==(s=='long-model'),name
            assert m['frame']['height']<=32 and m['frame']['height']>0,name
            assert fields['context']['text']==('暂未读到上下文' if s=='unknown' else '上下文占用 25%'),name
        # Actual sibling rectangles: columns don't overlap and account content precedes session.
        for i in range(len(w)):
            a=fields[f'window-{i}-amount']['frame'];b=fields[f'window-{i}-name']['frame']
            assert b['x']+b['width']+16<=a['x']+0.1,name
        assert fields['account-heading']['frame']['y']>fields['session-heading']['frame']['y'],name
for s in samples:
    a=next(f for f in r['frames'] if f['name']=='light-'+s);b=next(f for f in r['frames'] if f['name']=='dark-'+s)
    assert a['fields']==b['fields'] and a['windows']==b['windows'],s
renderer=json.loads((out/'renderer.json').read_text());assert renderer['swiftLanguageVersion']==6 and renderer['strictConcurrency'] and renderer['warningsAsErrors'] and not renderer['optimized']
sources=json.loads((out/'sources.json').read_text());assert len(sources)==518
for p,h in sources.items():assert hashlib.sha256((root/p).read_bytes()).hexdigest()==h,p
print(json.dumps({'status':'candidate_static_pass','frames':16,'sources':518,'integration':'not_run','context_source':'unqualified_synthetic','motion_hardware':'not_run'},ensure_ascii=False))
