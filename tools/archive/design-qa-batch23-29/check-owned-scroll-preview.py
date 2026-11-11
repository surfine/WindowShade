#!/usr/bin/env python3
"""Verify actual same-view AppKit scroll coordinates, not an implementation mirror."""
import hashlib
import json
import sys
from pathlib import Path

out = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[2]
data = json.loads((out / 'frames.json').read_text())
assert data['synthetic'] and data['actionsOnRealSources'] == 0
assert data.get('childrenReaped') and data.get('temporaryRemoved') and 'failure' not in data
assert not Path(data['temporaryRoot']).exists()
frames = data['frames']
assert len(frames) == 12 and len({f['name'] for f in frames}) == 12
failures = []
for f in frames:
    assert f['sameView'] and f['dark'] and not f['visible'] and not f['active'] and f['alpha'] == 0
    assert (out / (f['name'] + '.png')).stat().st_size > 1000
    a, b, stage = f['after'], f['before'], f['stage']
    if 'draft' in f:
        d = f['draft']
        assert d['matchesController'] and d['fontSize'] == 12
        assert d['height'] == 72 and d['replyHeight'] == 100
        assert d['radius'] == 12 and d['border'] == d['replyBorder'] == 0
        assert d['paddingX'] == 10 and d['paddingY'] == 8 and d['linePadding'] == 0
        assert not d['background'] and not d['replyBackground']
        if stage != 'empty':
            assert d['characters'] > 0
    assert 68 <= f['height'] <= 513.5
    if stage == 'empty':
        assert f['outputHidden'] and a['characters'] == 0
        continue
    assert a['textWidth'] > 0 and a['lineHeight'] > 0
    assert not f['outputHidden'] and a['documentHeight'] > a['visibleHeight'] and a['characters'] > b['characters']
    if stage in ['initial', 'bottom', 'inside-threshold'] and abs(a['gap']) > 1:
        failures.append({'name': f['name'], 'expected': 'follow end within 1pt', 'actual': a})
    if stage in ['top', 'outside-threshold'] and abs(a['origin'] - b['origin']) > 1:
        failures.append({'name': f['name'], 'expected': 'preserve origin within 1pt', 'before': b, 'actual': a})
    if stage == 'outside-threshold':
        assert abs(b['gap'] - 30) <= 1
    if stage == 'inside-threshold':
        assert abs(b['gap'] - 20) <= 1
sources = json.loads((out / 'sources.json').read_text())
assert len(sources) == 518
for p, sha in sources.items():
    assert hashlib.sha256((root / p).read_bytes()).hexdigest() == sha, p
print(json.dumps({'status': 'fail' if failures else 'pass', 'frames': len(frames), 'failures': failures}, ensure_ascii=False))
sys.exit(bool(failures))
