#!/usr/bin/env python3
"""把三份材料合并到全新仓库副本，不修改输入、不写用户配置、不构建 App。
示例: python3 tools/stage-all.py --repo /原始repo --part1 /part1 --part2 /part2 --out /全新候选repo
只接受委托中的完整固定快照；遇到当前项目新增改动需人工重定基线，不加 --force。
"""
import argparse, hashlib, json, os, shutil, sys, tempfile
from pathlib import Path

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def fail(message): raise ValueError(message)
def overlap(a,b): return a == b or a in b.parents or b in a.parents

def run():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo',type=Path,required=True)
    ap.add_argument('--part1',type=Path,required=True)
    ap.add_argument('--part2',type=Path,required=True)
    ap.add_argument('--part3',type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument('--out',type=Path,required=True)
    a=ap.parse_args()
    repo,p1,p2,p3=(p.resolve(strict=True) for p in (a.repo,a.part1,a.part2,a.part3))
    out=a.out.absolute()
    if out.exists() or out.is_symlink(): fail('输出已存在，拒绝覆盖')
    parent=out.parent.resolve(strict=True);out=parent/out.name
    if any(overlap(out,p) for p in (repo,p1,p2,p3)): fail('输出必须与所有输入分离')
    expected=json.loads((p3/'integration/input-sha256.json').read_text())
    originals={str(p.relative_to(repo)):p for p in repo.rglob('*') if p.is_file()}
    if set(originals)!=set(expected): fail('原仓库文件集合与固定快照不同')
    for rel,p in originals.items():
        if p.is_symlink() or sha(p)!=expected[rel]: fail('源文件校验失败: '+rel)
    if any(p.is_symlink() for p in repo.rglob('*')): fail('输入含符号链接，拒绝复制')
    edits=json.loads((p1/'contracts/privacy/log-replacements.json').read_text())+json.loads((p2/'patches/edits.json').read_text())+json.loads((p3/'patches/edits.json').read_text())
    texts={};applied=[]
    for edit in edits:
        rel=edit['path'];source=repo/rel
        if not source.is_file() or sha(source)!=edit.get('sha256',edit.get('source_sha256')): fail('补丁基线不匹配: '+rel)
        text=texts.get(rel,source.read_text())
        if text.count(edit['old'])!=1: fail('原文锚点不是唯一匹配: '+rel)
        texts[rel]=text.replace(edit['old'],edit['new'],1)
        applied.append({'path':rel,'package':edit.get('package','prior-part'),'originalLine':edit.get('line')})
    logger=json.loads((p1/'contracts/privacy/logger-source.json').read_text());rel=logger['path']
    if sha(repo/rel)!=logger['sha256']: fail('日志源文件基线不匹配')
    text=texts.get(rel,(repo/rel).read_text());start=text.index('final class WindowShadeLogger {');end=text.index('\nfunc wlog(',start)
    texts[rel]=text[:start]+(p1/'contracts/privacy/WindowShadeLogger.replacement.swift.txt').read_text().rstrip()+'\n'+text[end:]
    added={};origins={}
    def add(rel,source,origin):
        content=source.read_bytes()
        if rel in added and added[rel]!=content:
            if not (rel=='prototype/Core/CodexWire.swift' and origin=='part3'): fail('新增源码冲突: '+rel)
        if (repo/rel).exists() and (repo/rel).read_bytes()!=content: fail('新增文件会覆盖已有源文件: '+rel)
        added[rel]=content;origins[rel]=origin
    for part,name in ((p1,'part1'),(p2,'part2'),(p3,'part3')):
        for package in sorted((part/'packages').iterdir()):
            proto=package/'prototype'
            if proto.is_dir():
                for source in sorted(proto.rglob('*.swift')):
                    add('prototype/'+str(source.relative_to(proto)),source,name)
    for part in (p1,p2):
        if (part/'contracts/Contracts.swift').read_bytes()!=(p3/'contracts/Contracts.swift').read_bytes(): fail('共享合同版本不同，必须先人工审定')
    add('prototype/Core/Contracts.swift',p3/'contracts/Contracts.swift','canonical')
    add('prototype/App/InteractionCoordinator.swift',p2/'contracts/InteractionCoordinator.swift','part2')
    add('prototype/Support/SecureLogFile.swift',p1/'contracts/privacy/SecureLogFile.swift','part1')
    if 'prototype/Core/WS2Contracts.swift' in added or (repo/'prototype/Core/WS2Contracts.swift').exists(): fail('发现第二份共享合同，请先去重')
    staging=Path(tempfile.mkdtemp(prefix='ws2-stage-',dir=parent))
    try:
        tree=staging/'repo';shutil.copytree(repo,tree)
        for rel,text in texts.items(): (tree/rel).write_text(text)
        for rel,content in added.items():
            target=tree/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
        # ws-hook 有独立 @main，不能进入 App 源码自动扫描。
        helper=tree/'tools/ws2-hook';helper.mkdir(parents=True,exist_ok=True)
        shutil.copy2(p3/'packages/A2a/tools/ws-hook/main.swift',helper/'main.swift')
        helper.joinpath('build.sh').write_text("""set -eu\nHERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\nREPO=$(CDPATH= cd -- "$HERE/../.." && pwd)\nOUT=${1:?请提供显式输出路径}\nswiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library "$REPO/prototype/Support/WS2UnixSocket.swift" "$REPO/prototype/Support/WS2BoundedInput.swift" "$HERE/main.swift" -o "$OUT"\n""")
        report={'baselineFiles':len(expected),'editedFiles':sorted(texts),'replacementCount':len(edits)+1,'addedSwiftFiles':origins,'sourceUnaffected':True,'appBuilt':False,'appInstalled':False,'status':'CANDIDATE_SOURCE_ONLY'}
        tree.joinpath('WS2-STAGING.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        for rel,p in originals.items():
            if sha(p)!=expected[rel]: fail('暂存期间输入发生变化: '+rel)
        # 先原子占有输出目录名；存在时 mkdir 必须失败，不覆盖对方目录。
        out.mkdir()
        try:
            for child in tree.iterdir(): os.rename(child,out/child.name)
        except BaseException:
            # 只清理本工具刚建立的输出目录；绝不触碰输入。
            shutil.rmtree(out);raise
        print(json.dumps({'out':str(out),**report},ensure_ascii=False,indent=2))
    finally: shutil.rmtree(staging,ignore_errors=True)
if __name__=='__main__':
    try: run()
    except (OSError,ValueError,KeyError) as exc:
        print('ERROR: '+str(exc),file=sys.stderr);sys.exit(2)
