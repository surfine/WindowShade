import argparse,hashlib,json,pathlib,shutil
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);p.add_argument('--out',required=True);a=p.parse_args()
r=pathlib.Path(a.repo).resolve();out=pathlib.Path(a.out).resolve();root=pathlib.Path(__file__).resolve().parents[1]
if out.exists() or out == r or r in out.parents: raise SystemExit('Refuse existing output or output inside input repo')
edits=json.loads((root/'patches/edits.json').read_text())
for e in edits:
 src=r/e['path'];raw=src.read_bytes()
 if hashlib.sha256(raw).hexdigest()!=e['sha256'] or raw.decode().count(e['old'])!=1: raise SystemExit('STALE_INPUT '+e['path'])
out.mkdir(parents=True)
for e in edits:
 f=out/e['path'];f.parent.mkdir(parents=True,exist_ok=True);f.write_text((r/e['path']).read_text().replace(e['old'],e['new']))
for pkg in (root/'packages').iterdir():
 if not (pkg/'prototype').exists(): continue
 for f in (pkg/'prototype').rglob('*.swift'):
  dest=out/f.relative_to(pkg);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,dest)
for src,dst in [('contracts/Contracts.swift','prototype/Core/WS2Contracts.swift'),('contracts/InteractionCoordinator.swift','prototype/App/InteractionCoordinator.swift'),('dependencies/FocusTimer.swift','prototype/Core/FocusTimer.swift')]:
 dest=out/dst;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/src,dest)
print('PASS STAGED_NEW_DIRECTORY',out)
print('No input repository, user home, device, or running App was modified')
