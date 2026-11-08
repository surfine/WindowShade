#!/usr/bin/env python3
"""Stage pure packages into a new repo-shaped directory; no original repo writes, no app launch."""
from pathlib import Path
import argparse,hashlib,json,shutil,sys
p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
bundle=Path(__file__).resolve().parent.parent
if a.output.exists():sys.exit('STOP output already exists')
if a.output.resolve().is_relative_to(a.repo.resolve()):sys.exit('STOP output cannot be within source repo')
source=a.repo/'prototype/Core/ConductorGesture.swift';baseline=bundle/'baseline/ConductorGesture.swift'
if not source.is_file() or source.read_bytes()!=baseline.read_bytes():sys.exit('STOP ConductorGesture baseline differs')
entries={'prototype/Core/Contracts.swift':bundle/'contracts/Contracts.swift','prototype/Core/ConductorGesture.swift':source,'tests/support/WS2TestSupport.swift':bundle/'tests/support/WS2TestSupport.swift'}
for package in sorted((bundle/'packages').iterdir()):
    for prefix in ('prototype','tests'):
        for source in sorted((package/prefix).rglob('*')):
            if source.is_file():
                dest=str(source.relative_to(package))
                if dest in entries:sys.exit('STOP duplicate staged path: '+dest)
                entries[dest]=source
# Stop rather than overwrite a different implementation already installed in source repo.
for dest,source in entries.items():
    old=a.repo/dest
    if old.exists() and old.read_bytes()!=source.read_bytes() and dest!='prototype/Core/ConductorGesture.swift':
        sys.exit('STOP existing different file requires main-model merge: '+dest)
a.output.mkdir(parents=True)
for dest,source in entries.items():
    out=a.output/dest;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,out)
manifest={dest:hashlib.sha256(source.read_bytes()).hexdigest() for dest,source in entries.items()}
(a.output/'STAGED-SHA256.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'PASS stage: {len(entries)} files copied; source repo untouched')
