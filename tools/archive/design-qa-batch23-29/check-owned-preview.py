#!/usr/bin/env python3
"""Check a completed owned-session fixture; exit zero alone is insufficient."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1]).resolve()
def read(name):
    return json.loads((output / name).read_text())
def require(condition, message):
    if not condition:
        raise ValueError(message)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

try:
    report = read('owned-phases.json')
    frames = read('frames.json')['frames']
    require(report['childReaped'] and report['temporaryRemoved'], 'child/temp cleanup incomplete')
    require(not Path(report['temporaryRoot']).exists(), 'temporary directory still exists')
    require(report['controllerCount'] == 1, 'unexpected controller ownership')
    require(report['fixtureSHA256'] == digest(root / 'tests/fixtures/conductor-backend.py'), 'fixture changed')
    require(report['backendCopySHA256'] == digest(output / 'synthetic-preview-backend.py'), 'generated backend identity mismatch')
    require(len(frames) == 14, 'expected fourteen final phase captures')
    expected = ['before-launch', 'ready', 'ready-model-picker', 'draft', 'running', 'completed', 'stopped']
    check_count = 0
    for parent in ['light', 'dark']:
        checks = read(parent + '-input-checks.json')
        require(checks['passed'] and all(c['passed'] for c in checks['checks']), parent + ' input/resize checks failed')
        names = {c['name'] for c in checks['checks']}
        require({'before-marking-send-enabled', 'marked-text-disables-send', 'actual-panel-frame-expands', 'actual-panel-frame-restores', 'same-owner-resize-offscreen', 'revoked-send-disabled'} <= names, parent + ' missing boundary checks')
        check_count += len(checks['checks'])
        for state in expected:
            name = parent + '-' + state + '.png'
            matches = [f for f in frames if f['image'] == name]
            require(len(matches) == 1 and (output / name).is_file(), 'missing/duplicate frame: ' + name)
            frame = matches[0]
            require(not frame['intersectsScreen'] and not frame['activeApplication'], 'fixture escaped screen/activity bounds: ' + name)
            require(all(label['withinContent'] for label in frame['visibleLabels']), 'visible label exceeds content: ' + name)
            phase = ('idle' if parent == 'light' else 'stopped') if state == 'before-launch' else ('ready' if state in ['ready', 'ready-model-picker', 'draft'] else state)
            require(frame['phase'] == phase, 'incorrect actual phase: ' + name)
            if state in ['running', 'completed']:
                require('合成后端回复' in frame['replyText'], 'missing real synthetic reply: ' + name)
            if state != 'ready-model-picker':
                send = next(b for b in frame['buttons'] if b['title'] == '发送')
                require(send['enabled'] == (state == 'draft'), 'incorrect send projection: ' + name)
            if state == 'stopped':
                require(frame['reapsObserved'] >= 1, 'no observed reap: ' + name)
    sources = read('sources.json')
    for name, value in sources.items():
        require(name.startswith(('prototype/', 'tools/design-qa/')) and '..' not in Path(name).parts and (root / name).resolve().is_relative_to(root), 'unexpected source path')
        require(digest(root / name) == value, 'source changed: ' + name)
    print(json.dumps({'passed': True, 'frames': len(frames), 'input_and_resize_checks': check_count, 'current_inputs': len(sources), 'cleanup': True, 'scope': 'synthetic fixture only; real hardware/input/animation quality not proven'}, ensure_ascii=False))
except (OSError, KeyError, ValueError, StopIteration) as error:
    print('Owned preview verification FAILED: ' + str(error), file=sys.stderr)
    sys.exit(1)
