#!/usr/bin/env python3
"""Verify a complete synthetic media preview against current production inputs."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
try:
    frames = json.loads((out / 'frames.json').read_text())
    checks = json.loads((out / 'checks.json').read_text())
    assert len(frames) == 12 and len(checks) == 2, 'incomplete media receipts'
    expected = {'playing', 'paused', 'live', 'long-title', 'empty-routes', 'routes'}
    for parent in ['light', 'dark']:
        subset = [f for f in frames if f['image'].startswith(parent + '-')]
        assert {f['state'] for f in subset} == expected and len(subset) == 6
        for frame in subset:
            is_list = frame['state'] == 'routes'
            assert frame['synthetic'] and not frame['intersectsScreen'] and not frame['activeApplication']
            assert frame['panelAlpha'] == 0 and abs(frame['width'] - 421) < 0.1
            assert abs(frame['height'] - (290 if is_list else 176)) < 0.1
            assert abs(frame['contentWidth'] - 420) < 0.1
            assert abs(frame['contentHeight'] - (256.5 if is_list else 142)) < 0.1
            assert frame['listOpen'] == is_list and frame['routeCount'] == (5 if is_list else 0)
            assert frame['routeReads'] == (1 if frame['state'] in ['routes', 'empty-routes'] else 0)
            png = (out / frame['image']).read_bytes()
            assert png.startswith(b'\x89PNG\r\n\x1a\n')
        check = next(c for c in checks if c['parent'] == parent)
        assert check['passed'] and check['localPlayCallbacks'] == 1
        assert check['staleAndRevokedCallbacks'] == 0 and check['pendingTimersAfterRevoke'] == 0
    sources = json.loads((out / 'sources.json').read_text())
    for path, digest in sources.items():
        file = (root / path).resolve()
        assert path.startswith(('prototype/', 'tools/design-qa/')) and '..' not in Path(path).parts
        assert file.is_relative_to(root) and hashlib.sha256(file.read_bytes()).hexdigest() == digest, path
    print(json.dumps({'passed': True, 'synthetic_frames': len(frames), 'control_guard_reports': len(checks),
                      'current_inputs': len(sources), 'real_media_or_hardware': 'not_run'}))
except (AssertionError, OSError, KeyError, ValueError, StopIteration) as error:
    print('Media preview verification FAILED: ' + str(error), file=sys.stderr)
    sys.exit(1)
