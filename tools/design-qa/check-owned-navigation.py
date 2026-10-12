#!/usr/bin/env python3
"""Consume actual native navigation receipts, then the existing phase contract."""
import json
from pathlib import Path
import subprocess
import sys

output = Path(sys.argv[1]).resolve()
required = {
    'valid-navigation-delivers-once', 'exact-byte-limit-enables-navigation',
    'multibyte-over-limit-disables-navigation', 'over-limit-action-guards-navigation',
    'over-limit-navigation-keeps-local-draft', 'over-limit-navigation-keeps-last-accepted-draft',
    'marked-action-guards-navigation', 'marked-navigation-keeps-composition',
    'unmark-navigation-delivers-once', 'missing-destination-disables-navigation',
    'stale-action-guards-navigation', 'revoked-action-guards-navigation',
}
try:
    for parent in ['light', 'dark']:
        report = json.loads((output / (parent + '-input-checks.json')).read_text())
        checks = {item['name']: item for item in report['checks']}
        if not required <= checks.keys():
            raise ValueError(parent + ' missing navigation boundary receipts')
        if not all(checks[name]['passed'] for name in required):
            raise ValueError(parent + ' navigation boundary failed')
    frames = json.loads((output / 'frames.json').read_text())['frames']
    for parent in ['light', 'dark']:
        frame = next(f for f in frames if f['image'] == parent + '-draft.png')
        if not any(label['text'].startswith('long-project-') and len(label['text']) > 200
                   and label['withinContent'] for label in frame['visibleLabels']):
            raise ValueError(parent + ' missing bounded long project title')
        if frame['panelAlpha'] != 0:
            raise ValueError('fixture must stay transparent')
    subprocess.run([sys.executable, str(Path(__file__).with_name('check-owned-preview.py')),
                    str(output)], check=True)
    print('Navigation callbacks, UTF8/IME preservation, stale/revoke and long title: passed.')
except (OSError, ValueError, KeyError, StopIteration, subprocess.CalledProcessError) as error:
    print('Owned navigation verification FAILED: ' + str(error), file=sys.stderr)
    sys.exit(1)
