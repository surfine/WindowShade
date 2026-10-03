#!/usr/bin/env python3
"""Stage a verified PART3 candidate plus this overlay into a new directory. Never edits the base."""
import argparse, hashlib, json, os, shutil, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def scan(root):
    output={}
    for p in sorted(root.rglob('*')):
        if p.is_symlink(): raise ValueError(f'symlink refused: {p.relative_to(root)}')
        if p.is_file(): output[p.relative_to(root).as_posix()]=digest(p)
    return output
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--base',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();base=args.base.resolve(strict=True);out=args.out.absolute()
    if args.base.is_symlink() or args.out.is_symlink(): raise ValueError('symlink root refused')
    if out.exists(): raise ValueError('output already exists')
    if not out.parent.is_dir() or out.parent.resolve()!=out.parent: raise ValueError('output parent must exist and have no symlink')
    if out == base or base in out.parents or out in base.parents: raise ValueError('base/output overlap')
    manifest=json.loads((ROOT/'manifest.json').read_text())
    actual=scan(base)
    if actual!=manifest['baseFiles']: raise ValueError('base changed; do not force overlay onto a newer working tree')
    expected={r['path']:r['sha256'] for r in manifest['overlay']}
    if scan(ROOT/'overlay')!=expected: raise ValueError('overlay changed or damaged')
    # mkdir fails atomically when another process creates the destination first.
    out.mkdir(mode=0o700)
    try:
        for rel in actual:
            dst=out/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(base/rel,dst)
        for rel in expected:
            dst=out/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'overlay'/rel,dst)
        if scan(base)!=actual: raise ValueError('base was edited during staging')
        expected_final=actual|expected
        if scan(out)!=expected_final: raise ValueError('staged content verification failed')
    except Exception:
        # Retain the new failed staging directory for inspection; never clean an external user's path.
        raise
    print(json.dumps({'status':'staged, not built','baseFileCount':len(actual),'overlayFileCount':len(expected),
        'modifiedExisting':sum(r in actual for r in expected),'newFiles':sum(r not in actual for r in expected),
        'candidateFiles':len(expected_final),'output':str(out)},ensure_ascii=False,indent=2))
if __name__=='__main__':
    try: main()
    except (ValueError,OSError) as exc: print('REFUSED: '+str(exc),file=sys.stderr);sys.exit(2)
