#!/usr/bin/env python3
"""Record actual Foundation typecheck, syntax-only platform checks, and compiler versions."""
import argparse,hashlib,json,pathlib,platform,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--repo',required=True,type=pathlib.Path);a=p.parse_args();base=a.repo.resolve();r=base/'prototype';root=pathlib.Path(__file__).resolve().parent.parent;out=root/'validation';steps=[]
def run(argv):
 t=time.monotonic();v=subprocess.run([str(x) for x in argv],capture_output=True,text=True,timeout=45);steps.append({'argv':list(map(str,argv)),'exit_code':v.returncode,'stdout':v.stdout,'stderr':v.stderr,'elapsed_seconds':time.monotonic()-t});(out/'build-checks.json').write_text(json.dumps(steps,indent=2));print(v.stdout,end='');print(v.stderr,end='');
 if v.returncode: raise SystemExit(v.returncode)
core='Contracts WS2FocusWindowOwnership WS2DeviceInputGate PairingAttemptWindow PairingTLV CodexWire WS2CompanionFrame WS2ApprovalReview FocusTimer GamepadMapping WS2BoundedOutbox WS2FocusEffectPlan WS2SemanticInputRouter WS2DiagnosticTail WS2OwnedScope WS2SelectionModel WS2ConnectionBudget WS2StrictJSON WS2OwnedProtocolHost WS2QuitBarrier AgentSessions'.split()
support='WS2PeerRepository WS2PairSetupServer WS2PairSetupCrypto WS2FocusEffectExecutor WS2DuplexProcess WS2ProjectDirectory WS2LocalLaunchProfile WS2VersionProbe'.split()
# 本仓库把共享仲裁放在 Core/（v7 候选里在 App/），两边都要能找到。
app_files=['FocusTimerHost','WS2OwnedCodexSession','WS2OwnedLaunchController']
inputs=[r/'Core'/(x+'.swift') for x in core]+[r/'Support'/(x+'.swift') for x in support]
inputs+=[r/'Core/InteractionCoordinator.swift'] if (r/'Core/InteractionCoordinator.swift').exists() else [r/'App/InteractionCoordinator.swift']
inputs+=[r/'App'/(x+'.swift') for x in app_files]
run(['swiftc','--version']);run(['cc','--version']);run(['uname','-a']);run(['bash','-n',r/'build.sh'])
run(['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-I',r/'Native','-typecheck']+inputs)
old=json.loads((root/'sources/base-manifest.json').read_text());old=old.get('files',old)
changed=[]
for f in sorted(r.rglob('*.swift')):
 relative=str(f.relative_to(base));digest=hashlib.sha256(f.read_bytes()).hexdigest()
 if old.get(relative)!=digest:changed.append(f)
for f in changed:run(['swiftc','-frontend','-parse',f])
(out/'build-boundary.json').write_text(json.dumps({'foundation_files':len(inputs),'foundation_inputs':[str(x.relative_to(base)) for x in inputs],'syntax_only_files':len(changed),'syntax_only_inputs':[str(x.relative_to(base)) for x in changed],'mac_sdk':'NOT RUN','platform':platform.platform()},indent=2))
print('Foundation files',len(inputs),'Syntax-only files',len(changed))
