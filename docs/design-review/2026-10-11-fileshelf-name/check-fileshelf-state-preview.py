#!/usr/bin/env python3
"""Independent consumer of current production tile text and controlled shelf states."""
import hashlib
import json
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
try:
    frames = json.loads((out/'frames.json').read_text())
    cleanup = json.loads((out/'cleanup.json').read_text())
    states = {'empty','one','many','long-name','wide-name','unicode-name','missing','cleared','restored'}
    assert len(frames) == 18 and cleanup['syntheticFrames'] == 18
    assert cleanup['temporaryDirectoriesRemoved'] and cleanup['volatileDomainRestored']
    assert not cleanup['realUserFileActions']
    for parent in ['light','dark']:
        subset = [f for f in frames if f['image'].startswith(parent+'-')]
        assert len(subset)==9 and {f['state'] for f in subset}==states
        for f in subset:
            state=f['state']
            count=0 if state in {'empty','cleared'} else 7 if state=='many' else 2 if state=='missing' else 1
            assert f['count']==count and f['synthetic'] and f['typeIconsOnly']
            assert f['panelAlpha']==0 and not f['intersectsScreen'] and not f['activeApplication']
            assert abs(f['width']-561)<.1 and abs(f['height']-160)<.1
            assert abs(f['contentWidth']-560)<.1 and abs(f['contentHeight']-126.5)<.1
            assert len(f['names'])==len(f['tileRects'])==len(f['nameLines'])==count
            assert f['clearPending']==(state=='cleared')
            assert ('文件架空了' in f['visibleLabels'])==(state=='cleared')
            for i,(x,y,w,h) in enumerate(f['tileRects']):
                assert abs(x-(14+84*i))<.1 and y==0 and w==76 and h==104
            for name, rendered in zip(f['names'],f['nameLines']):
                lines=rendered['lines'];widths=rendered['widths']
                assert 1<=len(lines)<=2 and len(lines)==len(widths) and all(w<=68 for w in widths)
                assert rendered['joined']=='\n'.join(lines)
                assert ''.join(lines).count('…')<=1
                if state=='missing' and rendered['availability']=='missing':
                    assert len(lines)==2 and lines[1]=='找不到了' and lines[0].endswith('.txt')
                elif state!='missing':
                    ext=Path(name).suffix
                    if ext: assert lines[-1].endswith(ext), (state,lines,ext)
            if state=='unicode-name':
                # A family grapheme remains whole; no detached surrogate/component introduced by clipping.
                assert '👨‍👩‍👧‍👦' in ''.join(f['nameLines'][0]['lines'])
            if state=='missing':assert sum(r['availability']=='missing' for r in f['nameLines'])==1
            assert (out/f['image']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        check=json.loads((out/(parent+'-action-check.json')).read_text())
        assert all(check[k] for k in ['passed','freshRemoveAndUndo','originalOwnFileStillExists','staleRemovalBlocked','revokedRemovalBlocked'])
    sources=json.loads((out/'sources.json').read_text())
    for name,digest in sources.items():
        p=(root/name).resolve()
        assert p.is_relative_to(root) and hashlib.sha256(p.read_bytes()).hexdigest()==digest,name
    pairs={s:hashlib.sha256((out/f'light-{s}.png').read_bytes()).digest()==hashlib.sha256((out/f'dark-{s}.png').read_bytes()).digest() for s in states}
    assert all(pairs.values()),pairs
    print(json.dumps({'passed':True,'frames':len(frames),'action_reports':2,'current_inputs':len(sources),'parent_pairs_identical':9,'real_hardware_file_actions_and_thumbnails':'not_run'}))
except (AssertionError,OSError,ValueError,KeyError) as error:
    print('FileShelf states FAILED: '+str(error),file=sys.stderr);sys.exit(1)
