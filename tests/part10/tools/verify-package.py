#!/usr/bin/env python3
"""Verify the generated ZIP's paths, CRC and SHA256 tree without extracting it.

This checks integrity against the enclosed manifest, not publisher authenticity.
"""
from __future__ import annotations
import argparse, hashlib, json, pathlib, stat, sys, zipfile

def verify(path: pathlib.Path) -> dict:
    with zipfile.ZipFile(path) as z:
        infos=z.infolist()
        if len(infos)>50000 or sum(i.file_size for i in infos)>512*1024*1024:
            raise ValueError('archive exceeds verification budget')
        names=set(); roots=set(); members={}
        for i in infos:
            p=pathlib.PurePosixPath(i.filename)
            if '\\' in i.filename or '\x00' in i.filename or p.is_absolute() or '..' in p.parts:
                raise ValueError('unsafe archive path')
            if i.filename in names: raise ValueError('duplicate archive entry')
            names.add(i.filename)
            if stat.S_ISLNK(i.external_attr >> 16): raise ValueError('symlink entry')
            if not p.parts or p.as_posix()!=i.filename.rstrip('/'):
                raise ValueError('non-canonical archive path')
            roots.add(p.parts[0])
            if not i.is_dir():
                if len(p.parts)<2 or i.file_size>128*1024*1024: raise ValueError('invalid member')
                members[pathlib.PurePosixPath(*p.parts[1:]).as_posix()]=i
        if len(roots)!=1: raise ValueError('expected one package root')
        mi=members.get('MANIFEST.sha256.json')
        if mi is None or mi.file_size>16*1024*1024: raise ValueError('manifest missing or oversized')
        manifest=json.loads(z.read(mi))
        if manifest.get('format')!='sha256-tree-v1' or not isinstance(manifest.get('files'),dict):
            raise ValueError('unsupported manifest')
        expected=manifest['files']
        if set(expected)!=(set(members)-{'MANIFEST.sha256.json'}):
            raise ValueError('manifest file set differs')
        bad=z.testzip()
        if bad: raise ValueError('CRC failure: '+bad)
        for name,want in expected.items():
            digest=hashlib.sha256()
            with z.open(members[name]) as f:
                for chunk in iter(lambda:f.read(1024*1024),b''): digest.update(chunk)
            if digest.hexdigest()!=want: raise ValueError('SHA256 differs: '+name)
    return {'archive':path.name,'status':'VERIFIED','files_including_manifest':len(members),
            'manifest_members_verified':len(expected),'crc':'PASS',
            'archive_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'authenticity_or_application_test':False}

def main()->int:
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('archive',type=pathlib.Path);a=p.parse_args()
    try: result=verify(a.archive)
    except (OSError,ValueError,KeyError,TypeError,zipfile.BadZipFile) as e:
        print('REFUSED: '+str(e),file=sys.stderr);return 2
    print(json.dumps(result,ensure_ascii=False,indent=2));return 0
if __name__=='__main__':raise SystemExit(main())
