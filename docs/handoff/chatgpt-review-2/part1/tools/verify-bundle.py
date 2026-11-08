#!/usr/bin/env python3
"""Verify delivered bytes before running tests, which may update VALIDATION outputs."""
from pathlib import Path
import hashlib,sys
root=Path(__file__).resolve().parent.parent
manifest=root/'SHA256SUMS.txt'
if not manifest.is_file():sys.exit('FAIL missing SHA256SUMS.txt')
failures=[];count=0
for line in manifest.read_text().splitlines():
 expected,name=line.split('  ',1)
 path=root/name
 if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:failures.append(name)
 count+=1
if failures:
 print('FAIL changed or missing files: '+', '.join(failures));sys.exit(1)
print(f'PASS bundle-integrity: {count} delivered files match SHA256SUMS.txt')
