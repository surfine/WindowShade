#!/usr/bin/env python3
"""Run isolated numeric tests; never reads the app's repository or user data."""
import json
from pathlib import Path
import resource
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence'
OUT.mkdir(exist_ok=True)
# Avoid core-dump files from deliberately invalid integer conversions.
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
source = ROOT / 'checks/NumericBoundaryProbe.swift'
binary = ROOT / 'checks/numeric-probe'
cmd = ['swiftc', '-swift-version', '6', '-strict-concurrency=complete',
       '-warnings-as-errors', str(source), '-o', str(binary)]
subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=40)
normal = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=10)
(OUT / 'numeric-tests.log').write_text(normal.stdout)
records = []
for value in ['1', '-1', 'nan', 'inf', '4294967296']:
    result = subprocess.run([str(binary), 'unsafe-u32', value],
                            capture_output=True, text=True, timeout=10)
    records.append({'input': value, 'exit_code': result.returncode,
                    'stdout': result.stdout.strip(),
                    'diagnostic_prefix': result.stderr.splitlines()[:3]})
    if value == '1':
        assert result.returncode == 0
    else:
        assert result.returncode != 0
report = {
    'scope': 'Extracted numeric conversion only; NOT a macOS or AppKit run.',
    'source_commit_reviewed': '713d3884e31d4d6e698a7dc81df99219db1518b3',
    'swift': subprocess.run(['swift', '--version'], capture_output=True, text=True, check=True).stdout,
    'assertions_passed': 17,
    'unsafe_conversion_cases': records,
    'app_build_run': False,
    'camera_or_lock_or_bluetooth_run': False,
}
(OUT / 'numeric-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
