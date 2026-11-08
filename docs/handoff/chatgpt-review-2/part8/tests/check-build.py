#!/usr/bin/env python3
"""Actual typecheck for Foundation files; parse-only for Mac files. Never runs the app."""
import argparse,hashlib,json,pathlib,platform,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--repo',type=pathlib.Path,required=True);a=p.parse_args();base=a.repo.resolve();r=base/'prototype';P=pathlib.Path(__file__).resolve().parent.parent;out=P/'validation';steps=[]
def run(argv):
 st=time.monotonic();v=subprocess.run(list(map(str,argv)),text=True,capture_output=True,timeout=60)
 steps.append(dict(argv=list(map(str,argv)),exit_code=v.returncode,stdout=v.stdout,stderr=v.stderr,elapsed_seconds=time.monotonic()-st));(out/'build-checks.json').write_text(json.dumps(steps,ensure_ascii=False,indent=2));print(v.stdout,end='');print(v.stderr,end='')
 if v.returncode:raise SystemExit(v.returncode)
core='Contracts WS2FocusWindowOwnership WS2DeviceInputGate PairingAttemptWindow PairingTLV CodexWire WS2CompanionFrame WS2ApprovalReview FocusTimer GamepadMapping WS2BoundedOutbox WS2FocusEffectPlan WS2SemanticInputRouter WS2DiagnosticTail WS2OwnedScope WS2SelectionModel WS2ConnectionBudget WS2StrictJSON WS2OwnedProtocolHost WS2QuitBarrier AgentSessions WS2DeviceActionContracts WS2VisibleListInput WS2FoldEvidence'.split()
support='WS2PeerRepository WS2PairSetupServer WS2PairSetupCrypto WS2FocusEffectExecutor WS2DuplexProcess WS2ProjectDirectory WS2LocalLaunchProfile WS2VersionProbe'.split()
inputs=[r/'Core'/(x+'.swift') for x in core]+[r/'Support'/(x+'.swift') for x in support]+[r/'App'/(x+'.swift') for x in ['InteractionCoordinator','FocusTimerHost','WS2OwnedCodexSession','WS2OwnedLaunchController','WS2DeviceActionHost']]
run(['swiftc','--version']);run(['cc','--version']);run(['uname','-a']);run(['bash','-n',r/'build.sh'])
run(['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-I',r/'Native','-typecheck',*inputs])
old=json.loads((P/'sources/base-files.json').read_text());changed=[]
for f in sorted(r.rglob('*.swift')):
 if old.get(str(f.relative_to(base)))!=hashlib.sha256(f.read_bytes()).hexdigest():changed.append(f)
for f in changed:run(['swiftc','-frontend','-parse',f])
(out/'build-boundary.json').write_text(json.dumps(dict(foundation_count=len(inputs),foundation_inputs=[str(x.relative_to(base)) for x in inputs],syntax_count=len(changed),syntax_inputs=[str(x.relative_to(base)) for x in changed],mac_sdk='NOT RUN',platform=platform.platform()),indent=2))
print('Foundation:',len(inputs),'Syntax only:',len(changed))
