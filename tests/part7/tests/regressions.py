#!/usr/bin/env python3
"""Compile unchanged historical tests against the v7 candidate; never write to historical input."""
import argparse,json,pathlib,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--repo',required=True,type=pathlib.Path);p.add_argument('--history',required=True,type=pathlib.Path);p.add_argument('--batch',choices=['foundation','process'],required=True);p.add_argument('--report-dir',type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent.parent;out=a.report_dir or root/'validation';out.mkdir(exist_ok=True,parents=True);r=a.repo.resolve();h=a.history.resolve();s=r/'prototype';steps=[]
def run(args):
 start=time.monotonic();v=subprocess.run([str(x) for x in args],capture_output=True,text=True,timeout=50);steps.append(dict(argv=[str(x) for x in args],exit_code=v.returncode,elapsed_seconds=time.monotonic()-start,stdout=v.stdout,stderr=v.stderr));(out/('regressions-'+a.batch+'.json')).write_text(json.dumps(steps,indent=2,ensure_ascii=False));print(v.stdout,end='');print(v.stderr,end='');
 if v.returncode:raise SystemExit(v.returncode)
with tempfile.TemporaryDirectory(prefix='ws2-v7-regression-') as tmp:
 b=pathlib.Path(tmp);obj=b/'child.o'
 run(['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',s/'Native/WS2Child.c','-o',obj])
 flags=['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors']
 def suite(name,core,support,tests,args=(),native=False,library=False):
  sources=[s/'Core'/(x+'.swift') for x in core]+[s/x for x in support]+tests
  run(flags+(['-parse-as-library'] if library else [])+(['-I',s/'Native',obj] if native else [])+sources+['-o',b/name]);run([b/name]+list(args))
 if a.batch=='foundation':
  coord='Core/InteractionCoordinator.swift' if (s/'Core/InteractionCoordinator.swift').exists() else 'App/InteractionCoordinator.swift'
  suite('part6-core',['Contracts','WS2DiagnosticTail','WS2OwnedScope','WS2SelectionModel','WS2ConnectionBudget'],[coord,'Support/WS2ProjectDirectory.swift'],[h/'part6/tests/CoreTests.swift'],[out/'regression-part6-core-results.json'])
  suite('part6-wire',['Contracts','CodexWire','WS2StrictJSON'],[],[h/'part6/tests/WireProfileTests.swift'],[out/'regression-part6-wire-results.json',out/'regression-part6-wire-outbound.ndjson'])
  suite('part5-core',['Contracts','WS2FocusWindowOwnership','WS2DeviceInputGate','PairingAttemptWindow','PairingTLV','WS2BoundedOutbox','WS2FocusEffectPlan','WS2SemanticInputRouter'],['Support/WS2PeerRepository.swift','Support/WS2PairSetupServer.swift'],[h/'part5/tests/CoreTests.swift'],[out/'regression-part5-core-results.json'])
  suite('part4-core',['Contracts','CodexWire','WS2StrictJSON','FocusTimer','WS2CompanionFrame','WS2ApprovalReview','WS2DeviceInputGate','WS2FocusWindowOwnership'],[],[h/'part4/tests/CoreTests.swift'],[out])
  suite('part2',['Contracts','CodexWire','WS2StrictJSON','RemoteSessionGate','PresenceReadDeadline'],[coord],[h/'part2/tests/Part2CoreTests.swift'],[out/'regression-part2-outbound.ndjson'])
  suite('focus',['Contracts','FocusTimer'],[],[h/'part1/tests/support/WS2TestSupport.swift',h/'part1/packages/T1/tests/FocusTimerTests.swift'],library=True)
  suite('gesture',['ConductorGesture'],[],[r/'tests/ConductorGestureTests.swift'],library=True)
 else:
  for part,test,fixture,name in [('part6','ProcessTests.swift','child.py','part6-process'),('part5','ProcessTests.swift','fake-child.py','part5-process'),('part6','ExitInheritanceProbe.swift','child.py','PROC04')]:
   suite(name,['WS2BoundedOutbox','WS2DiagnosticTail'],['Support/WS2DuplexProcess.swift'],[h/part/'tests'/test],[h/part/'tests'/fixture,out/('regression-'+name+'-results.json')],native=True)
