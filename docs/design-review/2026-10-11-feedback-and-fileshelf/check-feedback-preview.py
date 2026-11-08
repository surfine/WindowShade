#!/usr/bin/env python3
"""Independent consumer for the production empty-route and disconnect repair."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
try:
    sources = json.loads((out / 'sources.json').read_text())
    for name, digest in sources.items():
        path = (root / name).resolve()
        assert path.is_relative_to(root) and hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
    owned = out / 'owned'
    # Both entries run in the same immutable production binary; this is its input manifest.
    assert json.loads((owned / 'sources.json').read_text()) == sources
    subprocess.run([sys.executable, str(root / 'tools/design-qa/check-owned-navigation.py'), str(owned)], check=True)
    owned_frames = json.loads((owned / 'frames.json').read_text())['frames']
    for frame in owned_frames:
        if frame['phase'] == 'stopped':
            assert frame['status'] == '已断开', frame['status']
    media = out / 'media'
    frames = json.loads((media / 'frames.json').read_text())
    checks = json.loads((media / 'checks.json').read_text())
    assert len(frames) == 12 and len(checks) == 4
    states = {'playing', 'paused', 'live', 'long-title', 'empty-routes', 'routes'}
    for parent in ['light', 'dark']:
        subset = [f for f in frames if f['image'].startswith(parent + '-')]
        assert len(subset) == 6 and {f['state'] for f in subset} == states
        for frame in subset:
            empty = frame['state'] == 'empty-routes'
            routes = frame['state'] == 'routes'
            height = 120.5 if empty else 256.5 if routes else 142
            host_height = 154 if empty else 290 if routes else 176
            assert frame['synthetic'] and frame['panelAlpha'] == 0
            assert not frame['intersectsScreen'] and not frame['activeApplication']
            assert abs(frame['width'] - 421) < .1 and abs(frame['height'] - host_height) < .1
            assert abs(frame['contentWidth'] - 420) < .1 and abs(frame['contentHeight'] - height) < .1
            assert frame['listOpen'] == (empty or routes)
            assert frame['routeReads'] == (1 if empty or routes else 0)
            assert frame['routeCount'] == (5 if routes else 0)
            assert frame['emptyVisible'] == empty
            assert frame['emptyText'] == '暂未找到设备'
            if empty:
                x, y, w, h = frame['emptyBounds']
                assert x >= 0 and y >= 0 and x+w <= 420 and y+h <= height
            assert (media / frame['image']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        play = next(c for c in checks if c['parent'] == parent and c['kind'] == 'play-guard')
        assert play['passed'] and play['localPlayCallbacks'] == 1 and play['staleAndRevokedCallbacks'] == 0
        empty = next(c for c in checks if c['parent'] == parent and c['kind'] == 'empty-feedback')
        assert empty['passed'] and empty['returned'] and empty['retryDeviceCount'] == 5 and empty['totalRouteReads'] == 2
        assert play['pendingTimersAfterRevoke'] == empty['pendingTimersAfterRevoke'] == 0
        for state in states:
            assert hashlib.sha256((media/f'light-{state}.png').read_bytes()).digest() == hashlib.sha256((media/f'dark-{state}.png').read_bytes()).digest()
    print(json.dumps({'passed': True, 'owned_frames': len(owned_frames), 'media_frames': len(frames), 'media_guard_reports': len(checks), 'current_inputs': len(sources), 'real_media_or_hardware': 'not_run'}))
except (AssertionError, OSError, KeyError, ValueError, StopIteration, subprocess.CalledProcessError) as error:
    print('Feedback preview FAILED: ' + str(error), file=sys.stderr)
    sys.exit(1)
