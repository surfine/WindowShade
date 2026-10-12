#!/usr/bin/env python3
import json,sys,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]);x=json.loads((out/'samples.json').read_text());r=x['records']
assert x['mainThread'] and x['delegateNil'] and not x['visible'] and not x['active'] and x['alpha']==0 and not x['productEntry'] and x['globalInputEvents']==0
assert len(r)==180
usable=0;maximum_error=0
for offset in range(0,len(r),6):
 group=r[offset:offset+6];assert len({s['time'] for s in group})==1
 values={(s['distance'],s['initialVelocity']):s['presentationX'] for s in group}
 assert all(v is not None for v in values.values())
 for speed in [-1,1]:
  small=values[(100,speed)]-values[(100,0)];large=values[(200,speed)]-values[(200,0)]
  if abs(small)>.1:
   error=abs(large-2*small);maximum_error=max(maximum_error,error);assert error<.03
   assert abs(large-small)>.05
   usable+=1
assert usable>=3,usable
inputs=json.loads((out/'inputs.json').read_text());assert len(inputs)==1
for f,h in inputs.items():assert hashlib.sha256((root/f).read_bytes()).hexdigest()==h
analysis={'actual_api':'CASpringAnimation','evidence':'speed perturbation doubles when travel doubles','normalized_velocity_supported':True,'eligible_comparisons':usable,'maximum_double_scale_error':maximum_error,'compositor_accepted':False,'instantaneous_velocity_measured':False,'source_count':1}
(out/'analysis.json').write_text(json.dumps(analysis,indent=2)+'\n');print('PASS actual Cocoa API normalized velocity:',analysis)
