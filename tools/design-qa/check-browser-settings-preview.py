#!/usr/bin/env python3
"""Consume the actual production-page fixture, including source identity."""
import hashlib
import json
import sys
from pathlib import Path

output = Path(sys.argv[1]).resolve()
phase = sys.argv[2]
root = Path(__file__).resolve().parents[2]
report = json.loads((output / 'frames.json').read_text())
frames = report['frames']
assert len(frames) == 8
assert report['argumentDomainRestored'] is True
assert report['actionsInvoked'] == report['persistentWrites'] == 0
assert len({f['name'] for f in frames}) == 8
for frame in frames:
    assert frame['selected'] == (0 if frame['trigger'] == 'off' else 2)
    assert 600 < frame['pageWidth'] <= 640
    assert frame['pageHeight'] > 600
    assert frame['visible'] is False and frame['active'] is False and frame['alpha'] == 0
    assert (output / (frame['name'] + '.png')).stat().st_size > 1000
    labels = frame['labels']
    assert '按窗口切换' in labels and '辅助功能' in labels and '屏幕录制' in labels
    has_false_promise = any('不接管原生 Command-Tab' in text for text in labels)
    assert has_false_promise == (phase == 'before')
    if phase == 'after':
        assert any('选 ⌘Tab 会换掉系统的 App 切换' in tip for tip in frame['toolTips'])
        for label in frame['labelBounds']:
            assert label['width'] > 0 and label['height'] > 0, label
            # Native label alignment frames can extend into the page's 28pt
            # host margin. Check actual viewport containment, not page origin.
            margin = (696 - frame['pageWidth']) / 2
            assert label['x'] + margin >= 0 and label['right'] + margin <= 696, label
for parent in ['light', 'dark']:
    for trigger in ['off', 'command']:
        top = next(f for f in frames if f['name'] == f'{parent}-{trigger}-top')
        bottom = next(f for f in frames if f['name'] == f'{parent}-{trigger}-bottom')
        assert top['scrollY'] == 0 and bottom['scrollY'] > 0
for name, digest in json.loads((output / 'sources.json').read_text()).items():
    path = Path(name) if Path(name).is_absolute() else root / name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
print(f'PASS {phase}: 8 actual settings frames, 2 trigger states, top/bottom, source hashes')
