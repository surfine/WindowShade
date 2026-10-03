#!/usr/bin/env python3
"""Exact v6-to-v7 staging into a new directory. Never overwrites or mutates input."""
import argparse,hashlib,json,os,pathlib,shutil,sys,tempfile

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def snapshot(root):
    if root.is_symlink() or not root.is_dir():raise ValueError('unsafe or missing directory')
    result={}
    for p in root.rglob('*'):
        if p.is_symlink():raise ValueError('symlink not permitted: '+str(p))
        if p.is_file():result[p.relative_to(root).as_posix()]=digest(p)
        elif not p.is_dir():raise ValueError('special object not permitted')
    return result

def relative(value):
    p=pathlib.PurePosixPath(value)
    if p.is_absolute() or not p.parts or '..' in p.parts or str(p)!=value:raise ValueError('unsafe manifest path')
    return p

def stage(package,base,out):
    package=pathlib.Path(package).resolve();raw_base=pathlib.Path(base).absolute();raw_out=pathlib.Path(out).absolute()
    if raw_base.is_symlink() or raw_out.is_symlink():raise ValueError('symlink input/output')
    base=raw_base.resolve();out=raw_out.resolve()
    if out.exists():raise ValueError('output already exists')
    if out==base or base in out.parents:raise ValueError('output must not be inside baseline')
    # Do not follow a caller-supplied output ancestor symlink into another tree.
    if raw_out!=out:raise ValueError('output ancestor must be canonical')
    manifest=json.loads((package/'manifest.json').read_text());expected=json.loads((package/'sources/base-manifest.json').read_text())
    actual=snapshot(base)
    if actual!=expected:raise ValueError('baseline mismatch; three-way merge required')
    changes=manifest['changes'];overlay=snapshot(package/'overlay');paths=[]
    for change in changes:
        rel=str(relative(change['path']));paths.append(rel)
        if actual.get(rel)!=change['baseSHA256']:raise ValueError('inconsistent base manifest')
        if overlay.get(rel)!=change['sha256']:raise ValueError('overlay hash mismatch')
    if len(paths)!=len(set(paths)) or set(paths)!=set(overlay):raise ValueError('overlay file set mismatch')
    out.parent.mkdir(parents=True,exist_ok=True)
    tmp=pathlib.Path(tempfile.mkdtemp(prefix='.ws2-stage-',dir=out.parent))
    try:
        candidate=tmp/'candidate';shutil.copytree(base,candidate)
        for change in changes:
            rel=change['path'];target=candidate/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(package/'overlay'/rel,target)
        final=snapshot(candidate);wanted=dict(actual)
        for change in changes:wanted[change['path']]=change['sha256']
        if final!=wanted:raise ValueError('output integrity failure')
        if out.exists():raise ValueError('output appeared during staging')
        # Container/file-system staging is not a cross-process filesystem CAS guarantee.
        candidate.rename(out)
        return {'base_files':len(actual),'output_files':len(final),'changed_files':len(changes),'original_preserved':snapshot(base)==actual,'output':str(out)}
    finally:shutil.rmtree(tmp,ignore_errors=True)

def main():
    p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--out',required=True);a=p.parse_args()
    try:result=stage(pathlib.Path(__file__).resolve().parent.parent,a.base,a.out)
    except (OSError,ValueError,KeyError,TypeError) as e:print('REFUSED: '+str(e),file=sys.stderr);return 2
    print(json.dumps(result,ensure_ascii=False,indent=2));return 0
if __name__=='__main__':raise SystemExit(main())
