#!/usr/bin/env python3
"""Geometry/state consumer; layer z-order, live materials/focus and motion remain inconclusive."""
import hashlib,json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]).resolve()
try:
    frames=json.loads((out/'frames.json').read_text())
    states={'intro-stuck','intro-hint','intro-no-notch','origin-unanswered','origin-windows','origin-ipad','origin-mac'}
    assert len(frames)==14
    for parent in ['light','dark']:
        subset=[f for f in frames if f['image'].startswith(parent+'-')]
        assert len(subset)==7 and {f['state'] for f in subset}==states
        for f in subset:
            assert f['width']==720 and f['height']==594
            assert f['syntheticStage'] and not f['visibleWindow'] and not f['activeApplication'] and f['alpha']==0
            assert not f['preferencesWritten'] and f['permissionQueries']==0
            assert f['nextEnabled']==(f['state']!='origin-unanswered')
            title='刚换 Mac？从刘海开始。' if f['page']==0 else '你之前常用哪个？'
            assert title in {v['text'] for v in f['labels']}
            for label in f['labels']:
                assert label['x']>=0 and label['y']>=0 and label['x']+label['width']<=720 and label['y']+label['height']<=594,label
            assert (out/f['image']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    sources=json.loads((out/'sources.json').read_text())
    for name,digest in sources.items():assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,name
    distinct={s:hashlib.sha256((out/f'light-{s}.png').read_bytes()).digest()!=hashlib.sha256((out/f'dark-{s}.png').read_bytes()).digest() for s in states}
    assert all(distinct.values()),distinct
    print(json.dumps({'passed':True,'geometry_state_frames':14,'current_inputs':len(sources),'system_appearance_pairs_distinct':7,'stage_z_order_live_material_focus_motion':'inconclusive','permission_functionality':'not_run'}))
except (AssertionError,ValueError,OSError,KeyError) as e:
    print('Welcome geometry/state FAILED: '+str(e),file=sys.stderr);sys.exit(1)
