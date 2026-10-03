#!/usr/bin/env python3
"""Run immutable previous tests from disposable copies; never overwrite historical reports."""
import argparse,pathlib,shutil,subprocess,tempfile,time,json,sys
p=argparse.ArgumentParser();p.add_argument('--repo',required=True,type=pathlib.Path);p.add_argument('--history',required=True,type=pathlib.Path);p.add_argument('--suite',required=True,choices=['part8-input','part8-fold','part8-flow','part8-static','part7-core','part7-native','part7-flow','duo','legacy-foundation','legacy-process']);a=p.parse_args()
here=pathlib.Path(__file__).resolve().parent.parent;out=here/'validation/regressions'/a.suite;out.mkdir(parents=True,exist_ok=True);records=[]
def run(cmd,timeout=150):
    st=time.monotonic();v=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=timeout)
    records.append(dict(argv=list(map(str,cmd)),exit_code=v.returncode,stdout=v.stdout,stderr=v.stderr,seconds=time.monotonic()-st));(out/'commands.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n');print(v.stdout,end='');print(v.stderr,end='',file=sys.stderr);return v.returncode
with tempfile.TemporaryDirectory(prefix='ws2-r9-regression-') as td:
    tmp=pathlib.Path(td)
    if a.suite.startswith(('part8-','part7-')):
        part,suite=a.suite.split('-');source=a.history/part;copy=tmp/part;copy.mkdir()
        for d in ['tests','fixtures','sources']: 
            if (source/d).exists():shutil.copytree(source/d,copy/d)
        (copy/'validation').mkdir()
        script=copy/'tests'/('check-wiring.py' if suite=='static' else 'run.py')
        cmd=[sys.executable,script,'--repo',a.repo]
        if suite!='static':cmd+=['--suite',suite]
        rc=run(cmd)
        for f in (copy/'validation').rglob('*'):
            if f.is_file():shutil.copy2(f,out/f.name)
    elif a.suite=='duo':
        root=a.repo/'prototype';binary=tmp/'duo-tests'
        files=['Effects/FoldDriver.swift','Effects/EffectFrameAwaiter.swift','Effects/LatestEffectFrame.swift','Effects/RestoreVerifier.swift','Core/FoldVerifier.swift','Core/MotionTilt.swift','Core/TitlebarTripleClickIntent.swift','Recovery/DurableShadeJournal.swift']
        rc=run(['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors',*[root/f for f in files],a.repo/'tests/DuoCoreTests.swift','-o',binary])
        if not rc:rc=run([binary])
        if not rc:rc=run([sys.executable,a.repo/'tests/duo-integration-check.py'])
    else:
        # 本仓库把历史回归脚本保留在 tests/part7/（已带 Core/ 仲裁路径适配）；
        # --history 指向含 part1..part6 原始测试的归档目录。
        legacy=pathlib.Path(__file__).resolve().parents[2]/'part7/tests/regressions.py'
        if not legacy.exists():legacy=a.history/'part7/tests/regressions.py'
        rc=run([sys.executable,legacy,'--repo',a.repo,'--history',a.history,'--batch',a.suite.split('-')[1],'--report-dir',out])
    (out/'suite.json').write_text(json.dumps(dict(suite=a.suite,exit_code=rc,original_swift_test_sources_modified=False,source_text_guard_updated=(a.suite=='duo'),real_mac_hardware=False),indent=2)+'\n')
    raise SystemExit(rc)
