#!/usr/bin/env python3
from pathlib import Path
import subprocess,json,datetime,platform,sys,re,os
B=Path(__file__).resolve().parent.parent
pmap=json.loads((B/'tools/package-map.json').read_text())
now=datetime.datetime.now(datetime.timezone.utc).isoformat();swift=subprocess.check_output(['swiftc','--version'],text=True).strip()
records=[]
def run(name,args,log):
    result=subprocess.run(args,cwd=B,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    header=f'UTC: {now}\nPlatform: {platform.platform()}\nCompiler: {swift}\nCommand: '+ ' '.join(args)+f'\nExit: {result.returncode}\n\n'
    log.parent.mkdir(parents=True,exist_ok=True);log.write_text(header+result.stdout)
    matches=re.findall(r'PASS ([^:\n]+): (\d+) cases, (\d+) assertions, 0 failures',result.stdout)
    record={'name':name,'exit':result.returncode,'log':str(log.relative_to(B)),'cases':sum(int(m[1]) for m in matches),'assertions':sum(int(m[2]) for m in matches)}
    records.append(record);print(('PASS' if result.returncode==0 else 'FAIL')+' '+name,flush=True)
    if result.returncode:print(result.stdout[-5000:],flush=True)
    return result.returncode
for pkg,(base,slug,deps) in pmap.items():run(pkg,['bash',str(B/f'packages/{pkg}/tests/run-{slug}-tests.sh')],B/f'packages/{pkg}/VALIDATION.txt')
run('CONTRACTS',['bash',str(B/'tests/run-contracts-tests.sh')],B/'contracts/VALIDATION.txt')
run('PRIVACY-LOG',['bash',str(B/'contracts/privacy/run-secure-log-tests.sh')],B/'contracts/privacy/VALIDATION.txt')
cores=[str(B/'contracts/Contracts.swift'),str(B/'baseline/ConductorGesture.swift')]+[str(p) for p in sorted((B/'packages').glob('*/prototype/Core/*.swift'))]
run('COMBINED-SWIFT6',['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-typecheck']+cores,B/'validation/combined-typecheck.txt')
# Optimized pure build matches production optimization flags, not its macOS SDK environment.
run('D1-OPTIMIZED',['swiftc','-swift-version','6','-strict-concurrency=complete','-warnings-as-errors','-O','-whole-module-optimization','-parse-as-library',str(B/'contracts/Contracts.swift'),str(B/'baseline/ConductorGesture.swift'),str(B/'packages/D1/prototype/Core/ConductorSession.swift'),str(B/'packages/D2/prototype/Core/ConductorCapabilities.swift'),str(B/'tests/support/WS2TestSupport.swift'),str(B/'packages/D1/tests/ConductorSessionTests.swift'),'-o',str(B/'.build/d1-optimized')],B/'validation/d1-optimized-build.txt')
if records[-1]['exit']==0:run('D1-OPTIMIZED-RUN',[str(B/'.build/d1-optimized')],B/'validation/d1-optimized-run.txt')
result={'timestamp_utc':now,'compiler':swift,'platform':platform.platform(),'records':records,'pure_unique_cases':sum(r['cases'] for r in records if r['name'] in pmap),'pure_unique_assertions':sum(r['assertions'] for r in records if r['name'] in pmap),'all_exits_zero':all(r['exit']==0 for r in records),'not_run':['macOS SDK build','Darwin ACL branch','actual devices','actual authorization backend','real agent transport','energy experiment','film rendering']}
(B/'validation/summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k in ['pure_unique_cases','pure_unique_assertions','all_exits_zero']},ensure_ascii=False),flush=True)
sys.exit(0 if result['all_exits_zero'] else 1)
