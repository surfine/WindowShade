#!/usr/bin/env python3
"""Reproduce two defects in the v8 production completion methods, not in AppKit."""
import argparse,pathlib,tempfile,subprocess,hashlib,json,time,sys
p=argparse.ArgumentParser();p.add_argument('--base',required=True,type=pathlib.Path);a=p.parse_args()
here=pathlib.Path(__file__).resolve().parent.parent;out=here/'validation';source=a.base/'prototype/App/FoldCompletion.swift'
original=source.read_text();records=[]
assert original.startswith('import Cocoa\n')
fixture='''import Foundation
typealias CGWindowID = UInt32
@MainActor final class AppDelegate { var foldWaiters: [CGWindowID:[UUID:(Bool)->Void]] = [:] }
@main enum Repro {
 @MainActor static func main() {
  let one=AppDelegate(); var a:[Bool]=[],b:[Bool]=[]
  _=one.registerFoldWaiter(id:77){a.append($0)}
  _=one.registerFoldWaiter(id:77){b.append($0)}
  one.settleFoldWaiters(id:77,success:true)
  let replacementWasAcknowledged = b == [true]
  let two=AppDelegate();var second:[Bool]=[];var secondToken:UUID?
  let first=two.registerFoldWaiter(id:99){_ in two.settleFoldWaiter(id:99,token:secondToken!,success:false)}
  secondToken=two.registerFoldWaiter(id:99){second.append($0)}
  two.settleFoldWaiters(id:99,tokens:[first,secondToken!],success:true)
  let batchWasReentered = second == [false]
  print("BASELINE_REPLACEMENT_ACK=\\(replacementWasAcknowledged)")
  print("BASELINE_SUCCESS_BATCH_REENTERED=\\(batchWasReentered)")
  if !replacementWasAcknowledged || !batchWasReentered {exit(1)}
 }
}
'''
with tempfile.TemporaryDirectory(prefix='ws2-baseline-repro-') as td:
    d=pathlib.Path(td);src=d/'Completion.swift';main=d/'Repro.swift';src.write_text(original.replace('import Cocoa\n','import Foundation\n',1));main.write_text(fixture)
    for cmd in [['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors',src,main,'-o',d/'repro'],[d/'repro']]:
        st=time.monotonic();v=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=40)
        records.append(dict(argv=list(map(str,cmd)),exit_code=v.returncode,stdout=v.stdout,stderr=v.stderr,seconds=time.monotonic()-st));print(v.stdout,end='');print(v.stderr,end='')
        if v.returncode:break
report={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'only_source_change':'import Cocoa replaced with import Foundation to compile field-only host','commands':records,'baseline_defects_reproduced':records[-1]['exit_code']==0 and len(records)==2,'mac_ui_executed':False,'meaning':'Two reproduced bookkeeping defects, not two fixed tests or a live window reproduction'}
(out/'baseline-reproduction.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
raise SystemExit(records[-1]['exit_code'])
