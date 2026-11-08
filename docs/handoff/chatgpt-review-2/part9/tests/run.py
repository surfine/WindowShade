#!/usr/bin/env python3
import argparse, pathlib, subprocess, tempfile, time, json, sys
p=argparse.ArgumentParser();p.add_argument('--repo',required=True,type=pathlib.Path);p.add_argument('--suite',choices=['regression','frame'],default='regression');a=p.parse_args()
here=pathlib.Path(__file__).resolve().parent.parent;report=here/'validation';report.mkdir(exist_ok=True)
records=[]
def run(cmd):
    start=time.monotonic();r=subprocess.run([str(x) for x in cmd],capture_output=True,text=True,timeout=90)
    records.append({'argv':[str(x) for x in cmd],'exit_code':r.returncode,'seconds':time.monotonic()-start,'stdout':r.stdout,'stderr':r.stderr})
    (report/(a.suite+'-commands.json')).write_text(json.dumps(records,indent=2,ensure_ascii=False)+'\n')
    print(r.stdout,end='');print(r.stderr,end='',file=sys.stderr)
    if r.returncode:raise SystemExit(r.returncode)
with tempfile.TemporaryDirectory(prefix='ws2-r9-') as td:
    binary=pathlib.Path(td)/'tests';root=a.repo/'prototype'
    inputs=[root/'Core/FoldVerifier.swift',root/'Core/WS2FoldCallbackStamp.swift',root/'App/FoldCompletion.swift',here/'tests/RegressionTests.swift'] if a.suite=='regression' else [root/'Effects/EffectFrameAwaiter.swift',here/'tests/FrameTests.swift']
    run(['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors',*inputs,'-o',binary])
    run([binary,report/(a.suite+'-results.json')])
