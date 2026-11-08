#!/usr/bin/env python3
"""Compile the exact production numeric/ID functions in a Foundation host; no AX/AppKit."""
from __future__ import annotations
import argparse,json,pathlib,subprocess,tempfile,sys,hashlib,resource,os
p=argparse.ArgumentParser();p.add_argument('--candidate',required=True,type=pathlib.Path);p.add_argument('--baseline',required=True,type=pathlib.Path);a=p.parse_args();P=pathlib.Path(__file__).resolve().parent.parent

def extract(text,name):
 start=text.index('    func '+name+'(');brace=text.index('{',start);depth=1;i=brace+1
 while depth:
  if text[i]=='{':depth+=1
  elif text[i]=='}':depth-=1
  i+=1
 return text[start:i]

def host(root):
 text=(root/'prototype/Recovery/Journal.swift').read_text()
 return 'import Foundation\nimport CoreFoundation\ntypealias CGWindowID = UInt32\nstruct Host {\n'+extract(text,'journalNumber')+'\n'+extract(text,'journalID')+'\n}\n'
cases=[('one','1','1'),('max','UInt64(UInt32.max)','UInt32.max'),('integer_double','42.0','42'),('NSNumber','NSNumber(value: 7)','7'),('missing','NSNull()','nil'),('zero','0','nil'),('negative','-1','nil'),('fractional','1.5','nil'),('nan','Double.nan','nil'),('positive_infinity','Double.infinity','nil'),('negative_infinity','-Double.infinity','nil'),('above_uint32','4294967296.0','nil'),('large_finite','Double.greatestFiniteMagnitude','nil'),('bool_true','true','nil'),('bool_false','false','nil'),('string','"12"','nil'),('array','[12]','nil'),('dictionary','["id":1]','nil'),('int64_max','Int64.max','nil'),('uint64_max','UInt64.max','nil'),('negative_fraction','-0.5','nil'),('leading_zero_string','"001"','nil'),('decimal_valid','NSNumber(value: UInt32.max)','UInt32.max'),('empty','""','nil')]
report={'kind':'EXACT_PRODUCTION_FUNCTIONS_FOUNDATION_HOST','appkit':'NOT_RUN','cases':[],'baseline':[],'commands':[]}
def command(argv,**kwargs):
 q=subprocess.run(argv,capture_output=True,text=True,timeout=40,**kwargs);report['commands'].append({'argv':list(map(str,argv)),'exit_code':q.returncode,'stdout':q.stdout,'stderr':q.stderr[:16000]});return q
with tempfile.TemporaryDirectory(prefix='ws2-journal-id-') as temp:
 t=pathlib.Path(temp);source=t/'test.swift';binary=t/'test'
 body=host(a.candidate)+'\n@main struct Tests { static func main() { let h=Host(); var failures=0\n'
 for name,value,expected in cases:
  body+=f'if h.journalID(["id": {value}]) == ({expected} as UInt32?) {{ print("PASS {name}") }} else {{ print("FAIL {name}"); failures += 1 }}\n'
 body+='if h.journalID([:]) == nil {print("PASS absent_key")} else {print("FAIL absent_key");failures += 1}\nexit(failures == 0 ? 0 : 1) } }\n'
 source.write_text(body);q=command(['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library',str(source),'-o',str(binary)])
 if q.returncode==0:
  q=command([str(binary)])
  report['cases']=[{'name':line.split(' ',1)[1],'status':'PASSED' if line.startswith('PASS ') else 'FAILED'} for line in q.stdout.splitlines()]
 else:report['compile_failed']=True
 # Old implementation is run only on synthetic data in a short-lived subprocess.
 old=t/'old.swift';oldbin=t/'old';old.write_text(host(a.baseline)+'\nlet values:[String:Any] = ["nan":Double.nan,"over":4294967296.0,"bool":true,"fraction":1.5]\nprint(String(describing:Host().journalID(["id": values[CommandLine.arguments[1]]!])))\n')
 compile_old=command(['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors',str(old),'-o',str(oldbin)])
 def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
 if compile_old.returncode==0:
  for name in ['nan','over','bool','fraction']:
   v=command([str(oldbin),name],preexec_fn=no_core,env={**os.environ,'SWIFT_BACKTRACE':'enable=no'})
   report['baseline'].append({'input':name,'exit_code':v.returncode,'stdout':v.stdout,'trap_observed':v.returncode<0})
report['test_count']=len(report['cases']);report['passed']=all(c['status']=='PASSED' for c in report['cases']) and len(report['cases'])==25
report['source_sha256']=hashlib.sha256((a.candidate/'prototype/Recovery/Journal.swift').read_bytes()).hexdigest()
(P/'validation/journal-id-tests.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['test_count','passed','baseline']},ensure_ascii=False,indent=2));raise SystemExit(0 if report['passed'] else 1)
