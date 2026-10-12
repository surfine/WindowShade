#!/usr/bin/env python3
"""Consume actual AppKit image/card rectangles and source identities."""
import hashlib
import json
import sys
from pathlib import Path

out = Path(sys.argv[1]).resolve(); root = Path(__file__).resolve().parents[2]
data = json.loads((out / 'frames.json').read_text()); frames = data['frames']
assert data['realSources'] == 0 and data['syntheticImages'] == 5
assert len(frames) == 82 and len({f['name'] for f in frames}) == 82
failures, narrow = [], []
def contained(a, b):
    return a['x'] >= b.get('x', 0)-0.01 and a['y'] >= b.get('y', 0)-0.01 and a['x']+a['width'] <= b.get('x',0)+b['width']+0.01 and a['y']+a['height'] <= b.get('y',0)+b['height']+0.01
for f in frames:
    assert not f['visible'] and not f['active'] and f['alpha'] == 0 and f['actions'] == 0
    assert not f['selected'] and f['hovered'] == f['expectedHovered'] and f['barHidden'] != (f['hovered'] or f['busy'])
    assert f['globalInputEvents'] == 0 and f['localHoverCallbacks'] == int(f['hovered'])
    assert f['busy'] == f['expectedBusy']
    buttons = f['buttons']; assert len(buttons) == 4 and len({b['id'] for b in buttons}) == 4
    assert sum(b['more'] and not b['hidden'] for b in buttons) == 1
    for button in buttons:
        if not button['hidden']:
            assert button['frame']['width'] == button['frame']['height'] == 28
    assert f['imagePresent'] and f['titleText'] == f['tooltip'] and f['wraps']
    assert (out / (f['name'] + '.png')).stat().st_size > 1000
    picture, title, bar, card = (f[k] for k in ['picture', 'title', 'bar', 'card'])
    assert all(v['width'] > 0 and v['height'] > 0 for v in [picture, title, bar, card])
    assert contained(picture, card) and contained(title, card) and contained(bar, card)
    assert title['y'] + title['height'] <= picture['y'] + 0.01
    assert bar['y'] >= title['y'] + title['height']
    ratio_error = abs(picture['width']/picture['height'] - f['imageWidth']/f['imageHeight'])
    if ratio_error > 1/min(picture['width'], picture['height']):
        failures.append({'name':f['name'],'aspect_error':ratio_error})
    assert f['thumbnailBounds']['width'] == picture['width'] and f['thumbnailBounds']['height'] == picture['height']
    assert f['thumbnailFrame']['width'] == picture['width'] and f['thumbnailFrame']['height'] == picture['height']
    assert abs(bar['width'] - f['barRequiredWidth']) < 0.01
    for button in buttons:
        if not button['hidden']:
            assert contained(button['frame'], {'width':bar['width'],'height':bar['height']})
    if (f['hovered'] or f['busy']) and picture['width'] >= 44 and not contained(bar, picture):
        failures.append({'name':f['name'],'expected':'toolbar inside picture','bar':bar,'picture':picture})
    if f['hovered'] and bar['x'] < picture['x']:
        narrow.append({'name':f['name'],'toolbar_left_overhang':picture['x']-bar['x'],'picture_width':picture['width']})
reuse = [f for f in frames if 'reuseStage' in f]
assert len(reuse) == 2 and all(f['sameCard'] for f in reuse)
assert [f['barRequiredWidth'] for f in reuse] == [128, 64]
assert [sum(not b['hidden'] for b in f['buttons']) for f in reuse] == [4, 2]
sources = json.loads((out / 'sources.json').read_text()); assert len(sources) == 518
for p,h in sources.items(): assert hashlib.sha256((root/p).read_bytes()).hexdigest() == h,p
print(json.dumps({'status':'fail' if failures else 'pass','actual_frames':len(frames),'failures':failures,'narrow_toolbar_facts':narrow}))
sys.exit(bool(failures))
