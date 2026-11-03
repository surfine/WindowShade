#!/usr/bin/env python3
"""Compile actual candidate files. The test bridge is explicitly synthetic; no AppKit shim."""
import argparse,json,pathlib,subprocess,tempfile,time,platform,sys
p=argparse.ArgumentParser();p.add_argument('--repo',type=pathlib.Path,required=True);p.add_argument('--suite',choices=['input','fold','flow'],default='input');a=p.parse_args()
here=pathlib.Path(__file__).resolve().parent.parent;out=here/'validation';out.mkdir(exist_ok=True)
R=a.repo.resolve()/'prototype';steps=[]
def run(cmd,timeout=60):
 st=time.monotonic()
 try:
  r=subprocess.run(list(map(str,cmd)),text=True,capture_output=True,timeout=timeout)
  steps.append(dict(argv=list(map(str,cmd)),exit_code=r.returncode,elapsed_seconds=time.monotonic()-st,stdout=r.stdout,stderr=r.stderr))
 except subprocess.TimeoutExpired as e:
  steps.append(dict(argv=list(map(str,cmd)),exit_code=None,status='TIMEOUT',elapsed_seconds=time.monotonic()-st));raise
 finally:(out/(a.suite+'-commands.json')).write_text(json.dumps(steps,ensure_ascii=False,indent=2))
 print(r.stdout,end='');print(r.stderr,end='')
 if r.returncode:raise SystemExit(r.returncode)
base=['Core/Contracts.swift','Core/GamepadMapping.swift','Core/WS2DeviceInputGate.swift','Core/WS2SelectionModel.swift','Core/WS2SemanticInputRouter.swift','Core/WS2DeviceActionContracts.swift','Core/WS2VisibleListInput.swift','App/WS2DeviceActionHost.swift']
with tempfile.TemporaryDirectory(prefix='ws2-r8-') as td:
 binary=pathlib.Path(td)/'tests';extra=[]
 if a.suite=='input':tests=['InputHarness.swift','InputTests.swift']
 elif a.suite=='fold':base=['Core/WS2FoldEvidence.swift'];tests=['FoldTests.swift']
 else:
  base += ['Core/WS2QuitBarrier.swift','Core/WS2StrictJSON.swift','Core/CodexWire.swift','Core/WS2OwnedProtocolHost.swift','Core/WS2BoundedOutbox.swift','Core/WS2DiagnosticTail.swift','Core/WS2OwnedScope.swift','Core/AgentSessions.swift','Support/WS2ProjectDirectory.swift','Support/WS2LocalLaunchProfile.swift','Support/WS2VersionProbe.swift','Support/WS2DuplexProcess.swift','App/WS2OwnedCodexSession.swift','App/WS2OwnedLaunchController.swift']
  obj=pathlib.Path(td)/'child.o';run(['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',R/'Native/WS2Child.c','-o',obj]);extra=['-I',R/'Native',obj];tests=['InputHarness.swift','InputFlowTests.swift']
 cmd=['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors',*extra,*[R/x for x in base],here/'tests/TestLog.swift',*[here/'tests'/x for x in tests],'-o',binary]
 run(cmd)
 args=[binary,out/(a.suite+'-results.json')]
 if a.suite=='flow':
  fixture=pathlib.Path(td)/'fake-codex.py'
  original=(here/'fixtures/fake-codex.py').read_text()
  fixture.write_text('#!'+str(pathlib.Path(sys.executable).resolve())+' -S\n'+'\n'.join(original.splitlines()[1:])+'\n')
  args.append(fixture)
 run(args)
