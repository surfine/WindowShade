#!/usr/bin/env python3
"""Text-level regression guards only. They cannot validate SDK types or actual device/window behavior."""
import argparse,json,pathlib
p=argparse.ArgumentParser();p.add_argument('--repo',required=True,type=pathlib.Path);a=p.parse_args();r=a.repo/'prototype';P=pathlib.Path(__file__).resolve().parent.parent
read=lambda s:(r/s).read_text();checks=[]
def ck(name,condition):checks.append(dict(name=name,result='PASS' if condition else 'FAIL',level='static source guard'))
gc=read('App/WS2GameControllerBridge.swift');disc=gc.split('private func reconcile()')[1].split('private func installHandler')[0]
ck('discovery does not install handlers','valueChangedHandler =' not in disc and 'handlerQueue =' not in disc)
ck('existing input handler refused','pad.valueChangedHandler == nil' in gc)
ck('background setting not assigned','shouldMonitorBackgroundEvents =' not in gc)
ck('handler release restores queue','e.controller.handlerQueue = queue' in gc and 'extendedGamepad?.valueChangedHandler = nil' in gc)
v=read('App/WS2ModelPickerView.swift')
ck('model page cannot call send or approve',all(x not in v for x in ['sendDraft(','.send(','.approve(','.consumeGrant(']))
ck('model adoption uses real controller','self.controller.chooseModel(id)' in v)
ck('page lease and key window checked','currentLease?() == expectedLease' in v and 'window?.isKeyWindow == true' in v)
ck('armed target visibly represented','松开 A 使用：' in v and 'input.onArmed =' in v)
ck('refocus refresh does not re-enable','Regaining focus refreshes local controls, but never re-enables a controller.' in v)
ad=read('App/WS2FoldEvidenceAdapter.swift')
ck('strict missing-value policy exists','func strictFoldObservation' in ad and 'case .none,.ownWindowOrderedOut,.quickLookClosed: return .unknown' in ad)
ck('retries retain transaction not entire state','let transactionID = state.foldTransactionID' in ad and 'live.foldTransactionID==transactionID' in ad)
sh=read('App/ShadeController.swift')
ck('physical attempt bound to ledger','foldEvidence.markMutation' in sh and 'mayCommitObservedFold' in sh and 'foldEvidence.bind' in sh)
ck('notch uses actual evidence caller','shadeWithEvidence' in read('App/Notch.swift'))
ck('read-only profile kept','WS2ReadOnlyProtocolHost' in read('App/WS2OwnedCodexSession.swift'))
(P/'validation/wiring-static.json').write_text(json.dumps(dict(checks=checks,application_build='NOT RUN',hardware='NOT RUN'),ensure_ascii=False,indent=2)+'\n')
for c in checks:print(c['result'],c['name'])
raise SystemExit(0 if all(c['result']=='PASS' for c in checks) else 1)
