#!/usr/bin/env python3
"""Consume actual hidden native usage output. JSON/finite/model identity checks
and AppKit glyph measurements are control/static evidence, not actual account,
VoiceOver, compositor, signed product lifecycle or hardware acceptance.
"""
import hashlib,json,math,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=Path(sys.argv[1]).resolve()
report=json.loads((out/'frames.json').read_text())
assert report['sourceControllers']==0 and report['actions']==0
frames=report['frames']
samples=['normal','low','low-updated','zero','unknown','expired','weekly','long-model','waiting','shared']
assert len(frames)==20
expect={'normal':24,'low':5,'low-updated':4,'zero':0,'unknown':None,'expired':5,'weekly':7,'long-model':24,'waiting':5,'shared':24}
for parent in ['light','dark']:
    batch=[f for f in frames if f['name'].startswith(parent+'-')]
    assert [f['sample'] for f in batch]==samples
    for f in batch:
        name=f['name'];sample=f['sample'];u=f['usage'];tile=f['tiles'][0]
        assert len(f['tiles'])==1 and f['windows']==0 and f['ongoing']==1 and f['completions']==1,name
        assert f['visible'] is False and f['active'] is False and f['alpha']==0 and f['canvasDark'] is True,name
        assert tile['dark'] is True and tile['id']==950 and tile['quantity']=='unknown',name
        assert u['leftPercent']==expect[sample],name
        amount=None if sample in ['unknown','waiting','shared'] else f"剩 {expect[sample]}%"
        assert tile['quantityText']==amount, f'{name}: quota amount absent/stale: {tile["quantityText"]!r} != {amount!r}'
        assert tile['accessibilityValue']==amount,name
        assert tile['renderedQuantityText']==(amount or ''),name
        assert tile['renderedQuantityWidth']<=tile['quantityAvailableWidth'],name
        assert tile['partHidden'] is True and all(x['hidden'] for x in tile['layerChildren']),name
        b=tile['frame']
        assert all(isinstance(v,(int,float)) and math.isfinite(v) for v in b.values()),name
        assert b['x']>=0 and b['y']>=0 and b['x']+b['width']<=f['width'] and b['y']+b['height']<=f['height'],name
        assert tile['subtitle'] in tile['tooltip'],name
        if sample=='low-updated':
            assert u['beforeUpdateValue']=='剩 5%' and u['afterUpdateValue']=='剩 4%' and u['retainedTileIdentity'] is True,name
            assert u['samePhaseSignature'] is True,name  # actual controller chooses quantity-only route
        if sample=='shared':
            assert tile['title']=='编程会话' and tile['subtitle']=='',name
            assert '演示模型' not in tile['tooltip'] and '剩' not in tile['accessibility'],name
        if sample=='expired':
            assert u['recovery'] is None and '等待用量更新' in u['detail'],name
            assert '马上恢复' not in u['subtitle'],name
            assert u['compactText']=='剩 5%',name  # clock cannot refill real quota
        if sample=='unknown':
            assert u['phase']=='running' and u['trailing']=='' and u['readingWindowCount']==0,name
        if sample=='waiting':
            assert u['phase']=='waiting' and u['trailing']=='等你',name
        if sample=='weekly':
            assert u['chosenWindowMinutes']==10080 and u['readingWindowCount']==2,name
for sample in samples:
    a=next(f for f in frames if f['name']=='light-'+sample)
    b=next(f for f in frames if f['name']=='dark-'+sample)
    assert a['tiles']==b['tiles'] and a['usage']==b['usage'],sample
renderer=json.loads((out/'renderer.json').read_text())
assert renderer['swiftLanguageVersion']==6 and renderer['strictConcurrency'] is True and renderer['warningsAsErrors'] is True and renderer['optimized'] is False
sources=json.loads((out/'sources.json').read_text());assert len(sources)==518
for name,digest in sources.items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,'source drift: '+name
print(json.dumps({'status':'pass_scoped_static_visual_motion_inconclusive','frames':len(frames),'source_count':len(sources),'quotas':'remaining actual projected glyph/AX; missing data no number; waiting wins','expiry':'waiting for new reading, clock does not refill','account/network/real source':'not_run','compositor/motion/hardware':'not_run'},ensure_ascii=False))
