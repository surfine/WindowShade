#!/usr/bin/env python3
"""Consume actual canvas descendants and source identities; static rendering only."""
import hashlib
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[2]
data = json.loads((output / 'frames.json').read_text())
frames = data['frames']
assert len(frames) == 12 and len({f['name'] for f in frames}) == 12
assert data['sourceControllers'] == data['actions'] == 0
for frame in frames:
    assert frame['visible'] is False and frame['active'] is False and frame['alpha'] == 0
    assert frame['canvasDark'] and frame['completions'] == 1
    tiles = frame['tiles']
    assert len(tiles) == frame['windows'] + frame['ongoing']
    assert len({t['id'] for t in tiles}) == len(tiles)
    assert (output / (frame['name'] + '.png')).stat().st_size > 1000
    previous_right = 0
    for tile in tiles:
        assert tile['dark']
        box = tile['frame']
        assert box['width'] == 124 and box['height'] > 0
        assert box['x'] >= previous_right and box['y'] >= 0
        assert box['x'] + box['width'] <= frame['width']
        assert box['y'] + box['height'] <= frame['height']
        previous_right = box['x'] + box['width']
        if tile['kind'] != 'tucked':
            assert tile['shelf'] is None
            if tile['kind'] == 'session':
                assert tile['quantity'] == 'unknown' and tile['quantityText'] is None
            if tile['kind'] == 'playing':
                assert tile['quantityText'] is None
            if frame['sample'] == 'unknown':
                assert tile['quantity'] == 'unknown'
    assert [t['kind'] for t in tiles[:frame['windows']]] == ['tucked'] * frame['windows']
    assert all(t['kind'] in ['session', 'playing', 'activity'] for t in tiles[frame['windows']:])
    if frame['windows'] and frame['ongoing']:
        left, right = tiles[frame['windows'] - 1]['frame'], tiles[frame['windows']]['frame']
        assert right['x'] - left['x'] - left['width'] == 17
    if frame['sample'] == 'stale-ended':
        assert tiles[frame['windows']]['stale']
        assert tiles[-1]['ended']
for name, digest in json.loads((output / 'sources.json').read_text()).items():
    path = Path(name) if Path(name).is_absolute() else root / name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
pairs = []
for sample in ['windows', 'activities', 'mixed', 'long', 'unknown', 'stale-ended']:
    a = (output / f'light-{sample}.png').read_bytes()
    b = (output / f'dark-{sample}.png').read_bytes()
    pairs.append({'sample': sample, 'identical': a == b})
print(json.dumps({'status': 'pass', 'actual_frames': 12, 'static_only': True, 'parent_pairs': pairs}))
