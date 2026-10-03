#!/usr/bin/env python3
"""Build and run the actual candidate files. Every invocation records argv, stdout and exit code."""
import argparse, json, os, pathlib, platform, shutil, subprocess, tempfile, time
p=argparse.ArgumentParser();p.add_argument('--repo',required=True,type=pathlib.Path);p.add_argument('--suite',choices=['core','flow','native'],required=True);p.add_argument('--report-dir',type=pathlib.Path);a=p.parse_args()
here=pathlib.Path(__file__).resolve().parent.parent;out=a.report_dir or here/'validation';out.mkdir(parents=True,exist_ok=True)
source=a.repo.resolve()/'prototype';steps=[]
def run(args,timeout=40):
    start=time.monotonic();result=subprocess.run([str(x) for x in args],capture_output=True,text=True,timeout=timeout)
    steps.append(dict(argv=[str(x) for x in args],exit_code=result.returncode,elapsed_seconds=time.monotonic()-start,stdout=result.stdout,stderr=result.stderr))
    (out/(a.suite+'-commands.json')).write_text(json.dumps(steps,indent=2,ensure_ascii=False))
    print(result.stdout,end='');print(result.stderr,end='')
    if result.returncode: raise SystemExit(result.returncode)
files=['Core/Contracts.swift','Core/WS2QuitBarrier.swift','Core/WS2StrictJSON.swift','Core/CodexWire.swift','Core/WS2OwnedProtocolHost.swift',
       'Core/WS2BoundedOutbox.swift','Core/WS2DiagnosticTail.swift','Core/WS2OwnedScope.swift','Core/AgentSessions.swift',
       'Support/WS2ProjectDirectory.swift','Support/WS2LocalLaunchProfile.swift','Support/WS2VersionProbe.swift',
       'Support/WS2DuplexProcess.swift','App/WS2OwnedCodexSession.swift','App/WS2OwnedLaunchController.swift']
with tempfile.TemporaryDirectory(prefix='ws2-build-') as d:
    build=pathlib.Path(d);obj=build/'child.o';binary=build/'suite'
    run(['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',source/'Native/WS2Child.c','-o',obj])
    swift=['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-I',source/'Native',obj]
    selected=[source/f for f in files]
    test={'core':'CoreTests.swift','flow':'FlowTests.swift','native':'NativeTests.swift'}[a.suite]
    run(swift+selected+[here/'tests/TestSupport.swift',here/'tests'/test,'-o',binary])
    report=out/(a.suite+'-results.json')
    fixture=build/'fake-codex.py'
    fixture.write_text('#!'+str(pathlib.Path(shutil.which('python3')).resolve())+' -S\n'+'\n'.join((here/'fixtures/fake-codex.py').read_text().splitlines()[1:])+'\n')
    args={'core':[report],'flow':[fixture,report],'native':[here/'fixtures/native-child.py',shutil.which('python3'),report]}[a.suite]
    run([binary]+args,timeout=65)
