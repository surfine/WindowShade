#!/usr/bin/env python3
"""Apply the part8 overlay only to an exact clean v7 candidate. Never edits the input."""
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, shutil, sys

class StageError(ValueError):
    pass

def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def relative(value: str) -> pathlib.PurePosixPath:
    if not isinstance(value, str) or not value or '\\' in value or '\x00' in value:
        raise StageError('invalid relative path')
    p = pathlib.PurePosixPath(value)
    if p.is_absolute() or '..' in p.parts or '.' in p.parts or str(p) != value:
        raise StageError('non-canonical relative path: ' + value)
    return p

def reject_symlink_chain(path: pathlib.Path) -> None:
    # macOS 的 /var、/tmp、/etc 是 Apple 自己的根级符号链接（Linux 上是真目录）；
    # 先按系统事实规范化这三个前缀，其余任何一段是符号链接仍然拒绝。
    resolved = str(path)
    for link, target in (('/var', '/private/var'), ('/tmp', '/private/tmp'), ('/etc', '/private/etc')):
        if resolved == link or resolved.startswith(link + '/'):
            resolved = target + resolved[len(link):]
            break
    for item in [pathlib.Path(resolved), *pathlib.Path(resolved).parents]:
        if item.is_symlink():
            raise StageError('symlink in input/output path: ' + str(item))

def inventory(root: pathlib.Path) -> dict[str, str]:
    reject_symlink_chain(root)
    if not root.is_dir():
        raise StageError('not a directory: ' + str(root))
    output = {}
    for current, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            p = pathlib.Path(current) / name
            if p.is_symlink():
                raise StageError('symlink is not admitted: ' + str(p))
        for name in files:
            p = pathlib.Path(current) / name
            if not p.is_file():
                raise StageError('non-regular input: ' + str(p))
            output[p.relative_to(root).as_posix()] = digest(p)
    return output

def apply(package: pathlib.Path, base: pathlib.Path, out: pathlib.Path) -> dict:
    for path in (package, base, out):
        reject_symlink_chain(path.absolute())
    # 全用 resolve()：macOS 上 /var 是符号链接，混用 absolute() 会让“输出在输入内”的比较失配。
    package, base, out = package.resolve(), base.resolve(), out.resolve()
    if out.exists() or out.is_symlink():
        raise StageError('output already exists')
    if not out.parent.is_dir():
        raise StageError('output parent must already exist')
    for source in (base, package):
        if out == source or source in out.parents or out in source.parents:
            raise StageError('output overlaps input')
    manifest = json.loads((package / 'manifest.json').read_text())
    expected = json.loads((package / 'sources/base-files.json').read_text())
    for key in expected:
        relative(key)
    if inventory(base) != expected:
        raise StageError('base file set or SHA256 differs from v7')
    changes = manifest['changes']
    keys = [entry['path'] for entry in changes]
    if len(keys) != len(set(keys)):
        raise StageError('duplicate change path')
    final = dict(expected)
    for entry in changes:
        path = relative(entry['path']).as_posix()
        if entry.get('base_sha256') != expected.get(path):
            raise StageError('incorrect per-file base hash: ' + path)
        if entry['operation'] not in ('add', 'replace') or (entry['operation'] == 'add') != (path not in expected):
            raise StageError('incorrect change operation: ' + path)
        source = package / 'overlay' / path
        reject_symlink_chain(source)
        if not source.is_file() or digest(source) != entry['sha256']:
            raise StageError('overlay missing or hash differs: ' + path)
        final[path] = entry['sha256']
    if inventory(package / 'overlay') != {x['path']: x['sha256'] for x in changes}:
        raise StageError('overlay has unlisted or missing files')
    if len(final) != manifest['result_file_count']:
        raise StageError('incorrect result count')
    # mkdir is an atomic refusal when another caller has already created this output.
    # This is a local staging tool, not a sandbox against hostile same-UID file replacement.
    out.mkdir(mode=0o700)
    try:
        shutil.copytree(base, out, dirs_exist_ok=True, copy_function=shutil.copy2)
        for entry in changes:
            destination = out / entry['path']
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(package / 'overlay' / entry['path'], destination)
        if inventory(out) != final or inventory(base) != expected:
            raise StageError('post-copy integrity check failed')
    except Exception:
        shutil.rmtree(out)
        raise
    return {'status': 'STAGED', 'base_file_count': len(expected), 'result_file_count': len(final),
            'replaced': sum(x['operation'] == 'replace' for x in changes),
            'added': sum(x['operation'] == 'add' for x in changes), 'out': str(out),
            'application_build': 'NOT RUN', 'runtime': 'NOT RUN'}

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base', required=True, type=pathlib.Path)
    p.add_argument('--out', required=True, type=pathlib.Path)
    p.add_argument('--package', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent.parent)
    args = p.parse_args()
    try:
        result = apply(args.package, args.base, args.out)
    except (StageError, OSError, ValueError, KeyError, TypeError) as e:
        print('REFUSED: ' + str(e), file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
