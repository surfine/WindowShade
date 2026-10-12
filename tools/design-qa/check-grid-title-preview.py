#!/usr/bin/env python3
"""Read the real grid title cell and bounds, not a recreated title algorithm."""
import hashlib
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).resolve()
phase = sys.argv[2]
root = Path(__file__).resolve().parents[2]
data = json.loads((output / 'frames.json').read_text())
frames = data['frames']
count = 32 if phase == 'after' else 16
assert len(frames) == count and len({f['name'] for f in frames}) == count
assert data['actions'] == 0 and not data['controllerStarted']
for frame in frames:
    assert frame['wraps'] == (phase == 'after')
    assert frame['breakMode'] == (0 if phase == 'after' else 4)
    assert frame['maxLines'] == 2 and frame['lastLineTruncates']
    assert frame['tooltip'] == frame['title']
    assert frame['visible'] is False and frame['active'] is False and frame['alpha'] == 0
    assert (output / (frame['name'] + '.png')).stat().st_size > 1000
    box, card = frame['titleFrame'], frame['cardBounds']
    assert box['width'] > 0 and box['height'] >= frame['lineHeight']
    if frame['sample'] != 'short':
        assert box['height'] >= 2 * frame['lineHeight']
    assert box['x'] >= 0 and box['y'] >= 0
    assert box['x'] + box['width'] <= card['width']
    assert box['y'] + box['height'] <= card['height']
    if frame['material'] == 'glass':
        assert frame['insideGlass']
if phase == 'after':
    before = {f['name']: f for f in json.loads((Path(sys.argv[3]) / 'frames.json').read_text())['frames']}
    for frame in frames:
        if frame.get('derivedParams', False):
            continue
        for key in ['titleFrame', 'cardBounds', 'font', 'lineHeight', 'tooltip']:
            assert frame[key] == before[frame['name']][key], (frame['name'], key)
for name, digest in json.loads((output / 'sources.json').read_text()).items():
    path = Path(name) if Path(name).is_absolute() else root / name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
print(f'PASS {phase}: {count} actual grid title cells/bounds, complete tooltips; static only')
