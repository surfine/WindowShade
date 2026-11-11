#!/usr/bin/env python3
"""Consume measured production file shelf frames with own-file cleanup proof."""
import hashlib
import json
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
try:
    frames = json.loads((out/'frames.json').read_text())
    cleanup = json.loads((out/'cleanup.json').read_text())
    assert len(frames) == 8 and cleanup['syntheticFrames'] == 8
    assert cleanup['temporaryDirectoriesRemoved'] and cleanup['volatileDomainRestored']
    assert not cleanup['realUserFileActions']
    for parent in ['light', 'dark']:
        subset = [f for f in frames if f['image'].startswith(parent+'-')]
        assert len(subset) == 4 and {f['state'] for f in subset} == {'empty','one','many','long-name'}
        for f in subset:
            count = 0 if f['state']=='empty' else 7 if f['state']=='many' else 1
            assert f['synthetic'] and f['typeIconsOnly'] and f['count']==count
            assert f['panelAlpha']==0 and not f['intersectsScreen'] and not f['activeApplication']
            assert abs(f['width']-561)<.1 and abs(f['height']-160)<.1
            assert abs(f['contentWidth']-560)<.1 and abs(f['contentHeight']-126.5)<.1
            assert abs(f['scrollWidth']-560)<.1 and abs(f['scrollHeight']-104)<.1
            assert len(f['names'])==count and len(f['tileRects'])==count
            for i,(x,y,w,h) in enumerate(f['tileRects']):
                assert abs(x-(14+84*i))<.1 and y==0 and w==76 and h==104
            if f['state']=='long-name': assert len(f['names'][0])>100
            assert (out/f['image']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    sources = json.loads((out/'sources.json').read_text())
    for name,digest in sources.items():
        p=(root/name).resolve()
        assert p.is_relative_to(root) and hashlib.sha256(p.read_bytes()).hexdigest()==digest,name
    pairs={s:hashlib.sha256((out/f'light-{s}.png').read_bytes()).digest()==hashlib.sha256((out/f'dark-{s}.png').read_bytes()).digest() for s in ['empty','one','many','long-name']}
    print(json.dumps({'passed':True,'frames':len(frames),'current_inputs':len(sources),'parent_pairs_identical':pairs,'file_actions_thumbnails_and_hardware':'not_run'}))
except (AssertionError,OSError,KeyError,ValueError) as error:
    print('FileShelf preview FAILED: '+str(error),file=sys.stderr);sys.exit(1)
