#!/usr/bin/env python3
"""Apply the part5 overlay to an exact v4 snapshot, never to an existing output or original workspace."""
import argparse, hashlib, json, shutil, sys
from pathlib import Path

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def inventory(root):
    entries={}
    for path in sorted(root.rglob('*')):
        if path.is_symlink(): raise ValueError('symlink is not admitted: '+str(path))
        if path.is_file(): entries[path.relative_to(root).as_posix()]=digest(path)
    return entries

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--base',required=True,type=Path); parser.add_argument('--out',required=True,type=Path)
    args=parser.parse_args(); root=Path(__file__).resolve().parents[1]; base=args.base.resolve(); out=args.out.resolve()
    manifest=json.loads((root/'manifest.json').read_text())
    if not base.is_dir(): raise ValueError('base is not an existing directory')
    if out.exists() or out==base or base in out.parents or out in base.parents or out==root or root in out.parents:
        raise ValueError('output must be new and outside both base and part5')
    observed=inventory(base)
    if observed != manifest['base_files']:
        changed=sorted(set(observed)^set(manifest['base_files']))+[p for p in observed.keys()&manifest['base_files'].keys() if observed[p]!=manifest['base_files'][p]]
        raise ValueError('baseline mismatch: '+', '.join(changed[:12]))
    overlay=inventory(root/'overlay')
    if overlay != {e['path']:e['sha256'] for e in manifest['overlay']}:
        raise ValueError('overlay mismatch; do not apply an unreviewed replacement')
    expected=dict(observed); expected.update(overlay)
    # Exclusive output creation preserves existing directories. Incomplete outputs are removed only by this call.
    out.parent.mkdir(parents=True,exist_ok=True); out.mkdir()
    try:
        shutil.copytree(base,out,dirs_exist_ok=True)
        for rel in overlay:
            dest=out/rel; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(root/'overlay'/rel,dest)
        actual=inventory(out)
        if actual!=expected: raise ValueError('staged content mismatch')
        if inventory(base)!=observed: raise ValueError('base changed while staging')
    except BaseException:
        shutil.rmtree(out); raise
    report={'status':'STAGED_NOT_MAC_BUILT','base_files':len(observed),'output_files':len(expected),
            'modified':sum(1 for rel in overlay if rel in observed),'added':sum(1 for rel in overlay if rel not in observed),
            'output':str(out),'original_unchanged':True}
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':
    try: main()
    except (ValueError,OSError,KeyError) as error: print('REFUSED: '+str(error),file=sys.stderr); sys.exit(2)
