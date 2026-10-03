#!/usr/bin/env python3
"""Apply part6 only to the exact v5 candidate, never in place. No remote or home writes."""
from pathlib import Path
import argparse,hashlib,json,shutil,sys,os

def hashes(root:Path):
    values={}
    for p in sorted(root.rglob('*')):
        if p.is_symlink(): raise ValueError(f'symlink not accepted: {p}')
        if p.is_file(): values[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
    return values

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True);parser.add_argument('--out',type=Path,required=True);parser.add_argument('--report',type=Path)
    args=parser.parse_args();root=Path(__file__).resolve().parents[1]
    base=args.base.resolve();out=args.out.resolve();manifest=json.loads((root/'manifest.json').read_text())
    if out.exists() or out==base or base in out.parents or out in base.parents: raise ValueError('output must be a new independent directory')
    if hashes(base)!=manifest['base']:raise ValueError('baseline SHA256/file-set mismatch; use a three-way merge for a newer workspace')
    if hashes(root/'overlay')!=manifest['overlay']:raise ValueError('overlay SHA256/file-set mismatch')
    for name in manifest['overlay']:
        p=Path(name)
        if p.is_absolute() or '..' in p.parts:raise ValueError('invalid overlay path')
    # Exclusive mkdir prevents overwriting a destination created after the validation step.
    out.mkdir(parents=True,exist_ok=False)
    try:
        shutil.copytree(base,out,dirs_exist_ok=True)
        for name in manifest['overlay']:
            target=out/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/'overlay'/name,target)
        expected=dict(manifest['base']);expected.update(manifest['overlay'])
        if hashes(out)!=expected:raise ValueError('candidate verification failed')
    except BaseException:
        shutil.rmtree(out);raise
    result={'status':'STAGED','inputFiles':len(manifest['base']),'outputFiles':len(expected),'changes':manifest['changes'],'baseUnchanged':hashes(base)==manifest['base']}
    if args.report:args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':'STAGED','outputFiles':len(expected)},ensure_ascii=False))
if __name__=='__main__':
    try: main()
    except (OSError,ValueError,KeyError) as exc: print('REFUSED:',exc,file=sys.stderr);sys.exit(2)
