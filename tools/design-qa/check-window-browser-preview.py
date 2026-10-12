#!/usr/bin/env python3
"""Actual content-view state/layout checks; no compositor or real-window claims."""
import hashlib
import json
import math
import sys
from pathlib import Path

output = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[2]
data = json.loads((output / 'frames.json').read_text())
frames = data['frames']
assert len(frames) == 36 and len({f['name'] for f in frames}) == 36
assert data['controllerStarted'] is False and data['actions'] == 0
expected = {'empty': 0, 'no-match': 0, 'one': 1, 'many': 6,
            'long-list': 7, 'busy-list': 7, 'narrow-list': 3, 'busy-unknown': 3, 'no-permission': 3}
for frame in frames:
    assert frame['records'] == expected[frame['sample']]
    assert frame['visible'] is False and frame['active'] is False and frame['alpha'] == 0
    assert frame['actions'] == frame['cachedThumbnails'] == 0
    assert (output / (frame['name'] + '.png')).stat().st_size > 1000
    assert frame['searchVisible'] == (frame['sample'] not in ['one', 'many'])
    if frame['sample'] == 'empty':
        assert '没有可显示的窗口' in frame['labels']
    if frame['sample'] == 'no-match':
        assert '没有匹配的窗口' in frame['labels']
    if frame['sample'] == 'no-permission':
        assert any('打开' in b['title'] and '屏幕录制' in b['title'] for b in frame['buttons'])
    if frame['records']:
        assert any(text.startswith('季度报告 — ') and len(text) > 100 for text in frame['labels'])
        assert frame['visibleKeys']
    if frame['sample'] in ['one', 'many', 'busy-unknown']:
        assert 'firstCard' in frame
    for row in frame['rows']:
        title, actions = row['title'], row['actions']
        assert title['x'] + title['width'] + 8 <= actions['x'] + 0.5, (frame['name'], row)
        assert actions['width'] == row['requiredWidth']
        assert row['titleTooltip'] in frame['labels']
        for status in row['status']:
            if status['text']:
                box = status['frame']
                assert box['x'] + box['width'] + 8 <= actions['x'] + 0.5
    if frame['requestedMaterial'] == 'paper':
        assert frame['material'] == 'paper' and not frame['insideGlass']
    if frame['material'] == 'glass':
        assert frame['insideGlass']
    assert frame['corner'] == 13
    for key in ['list', 'search', 'header', 'footer']:
        assert all(math.isfinite(v) for v in frame[key].values())
    for key in ['list'] + (['search'] if frame['searchVisible'] else []):
        box = frame[key]
        assert box['width'] > 0 and box['height'] > 0
        assert box['x'] >= -0.5 and box['y'] >= -0.5
        assert box['x'] + box['width'] <= frame['width'] + 0.5
        assert box['y'] + box['height'] <= frame['height'] + 0.5
    if 'firstCard' in frame:
        card = frame['firstCard']
        for key in ['title']:
            box = card[key]
            assert box['width'] > 0 and box['height'] > 0
            assert box['x'] >= -0.5 and box['y'] >= -0.5
            assert box['x'] + box['width'] <= card['bounds']['width'] + 0.5
            assert box['y'] + box['height'] <= card['bounds']['height'] + 0.5
for name, digest in json.loads((output / 'sources.json').read_text()).items():
    path = Path(name) if Path(name).is_absolute() else root / name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
print('PASS 36 actual browser states, native layout, text/action separation, material host, source hashes; static only')
