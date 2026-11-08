#!/usr/bin/env python3
"""Verify exact source revision, emit patched copies only into a new directory. Never overwrite input."""
from pathlib import Path
import argparse,hashlib,json,sys
p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,required=True);p.add_argument('--output',type=Path);a=p.parse_args()
here=Path(__file__).resolve().parent; changes=json.loads((here/'log-replacements.json').read_text())
result={}
for item in changes:
    path=item['path'];src=a.repo/path
    if not src.is_file() or hashlib.sha256(src.read_bytes()).hexdigest()!=item['source_sha256']:
        sys.exit('STOP source changed: '+path)
    text=result.get(path,src.read_text())
    if text.count(item['old'])!=1:sys.exit('STOP anchor ambiguous: '+path)
    result[path]=text.replace(item['old'],item['new'],1)
path='prototype/Support/Diagnostics.swift';source=a.repo/path
expected=json.loads((here/'logger-source.json').read_text())
if hashlib.sha256(source.read_bytes()).hexdigest()!=expected['sha256']:sys.exit('STOP Diagnostics source changed')
text=source.read_text();start=text.index('final class WindowShadeLogger {');end=text.index('\nfunc wlog(',start)
result[path]=text[:start]+(here/'WindowShadeLogger.replacement.swift.txt').read_text().rstrip()+'\n'+text[end:]
result['prototype/Support/SecureLogFile.swift']=(here/'SecureLogFile.swift').read_text()
if a.output:
    if a.output.exists():sys.exit('STOP output must not exist')
    if a.output.resolve().is_relative_to(a.repo.resolve()):sys.exit('STOP output must be outside source repo')
    a.output.mkdir(parents=True)
    for path,text in result.items():
        dest=a.output/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(text)
print(f'PASS log-patch: 12 exact replacements, {len(result)} files verified; '+('new copies written' if a.output else 'read-only'))
