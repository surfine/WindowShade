#!/usr/bin/env python3
import argparse,pathlib,json,subprocess,time,hashlib,platform
p=argparse.ArgumentParser();p.add_argument('--repo',required=True,type=pathlib.Path);a=p.parse_args();r=a.repo/'prototype';here=pathlib.Path(__file__).resolve().parent.parent;out=here/'validation';records=[]
def run(cmd):
 st=time.monotonic();v=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=80)
 records.append(dict(argv=list(map(str,cmd)),exit_code=v.returncode,stdout=v.stdout,stderr=v.stderr,seconds=time.monotonic()-st));(out/'build-commands.json').write_text(json.dumps(records,indent=2,ensure_ascii=False)+'\n');print(v.stdout,end='');print(v.stderr,end='')
 if v.returncode:raise SystemExit(v.returncode)
core='Contracts WS2FocusWindowOwnership WS2DeviceInputGate PairingAttemptWindow PairingTLV CodexWire WS2CompanionFrame WS2ApprovalReview FocusTimer GamepadMapping WS2BoundedOutbox WS2FocusEffectPlan WS2SemanticInputRouter WS2DiagnosticTail WS2OwnedScope WS2SelectionModel WS2ConnectionBudget WS2StrictJSON WS2OwnedProtocolHost WS2QuitBarrier AgentSessions WS2DeviceActionContracts WS2VisibleListInput WS2FoldEvidence FoldVerifier WS2FoldCallbackStamp'.split()
support='WS2PeerRepository WS2PairSetupServer WS2PairSetupCrypto WS2FocusEffectExecutor WS2DuplexProcess WS2ProjectDirectory WS2LocalLaunchProfile WS2VersionProbe'.split()
inputs=[r/'Core'/(s+'.swift') for s in core]+[r/'Support'/(s+'.swift') for s in support]+[r/'App'/(s+'.swift') for s in ['InteractionCoordinator','FocusTimerHost','WS2OwnedCodexSession','WS2OwnedLaunchController','WS2DeviceActionHost']]
inputs.append(r/'Effects/EffectFrameAwaiter.swift')
for cmd in [['swiftc','--version'],['cc','--version'],['uname','-a'],['bash','-n',r/'build.sh']]:run(cmd)
run(['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-I',r/'Native','-typecheck',*inputs])
base=json.loads((here/'base-files.json').read_text());changed=[f for f in sorted(r.rglob('*.swift')) if hashlib.sha256(f.read_bytes()).hexdigest()!=base.get(str(f.relative_to(a.repo)))]
for f in changed:run(['swiftc','-frontend','-parse',f])
(out/'build-boundary.json').write_text(json.dumps(dict(foundation_count=len(inputs),foundation_sources=[str(p.relative_to(a.repo)) for p in inputs],syntax_only_count=len(changed),syntax_only_sources=[str(p.relative_to(a.repo)) for p in changed],mac_sdk='NOT RUN',environment=platform.platform()),indent=2)+'\n')
print('Foundation:',len(inputs),'Parse only:',len(changed),'Mac SDK: NOT RUN')
