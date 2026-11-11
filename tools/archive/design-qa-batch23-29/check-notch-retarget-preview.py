#!/usr/bin/env python3
"""Actual layer/configuration baseline; reports direction evidence, never certifies FPS/compositor."""
import json,sys,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]);x=json.loads((out/'retarget.json').read_text());records=x['records']
assert x['overrideRestored'] and x['cacheOnly'] and not x['compositorAccepted'] and not x['productEntry']
assert x['realSources']==x['globalInputEvents']==0
assert len(records)==30
for r in records:
 assert r['mainThread'] and r['delegateNil'] and not r['visible'] and not r['active'] and r['alpha']==0
 assert r['model']['width']>0 and r['model']['height']>0
 if r['reduced']:assert not r['animations'],r['stage']
 for a in r['animations']:assert a['mass']>0 and a['stiffness']>0 and a['damping']>=0 and a['duration']>0 and a['additive']
reg={r['stage']:r for r in records if not r['reduced']}
a,b=reg['open-after'],reg['open-sample'];reverse=reg['reverse-after']
def mid_y(rect):return rect['y']+rect['height']/2
analysis={'kind':'configuration_and_hidden_presentation_only','compositor_pass':False,'instantaneous_velocity_measured':False}
if a['presentation'] is not None and b['presentation'] is not None:
 incoming=mid_y(b['presentation'])-mid_y(a['presentation'])
 remaining=mid_y(reverse['model'])-mid_y(b['presentation'])
 springs=[v for v in reverse['animations'] if v['key']=='morph.position']
 analysis.update(incoming_mid_y_delta=incoming,new_target_mid_y_delta=remaining,retarget_initial_velocity=[v['velocity'] for v in springs])
 old_live=any(v['key']=='morph.position' for v in b['animations'])
 if old_live and abs(incoming)>0.5 and abs(remaining)>0.5 and incoming*remaining<0 and springs:
  analysis['direction_configuration']='opposite_incoming_requires_negative'
  analysis['configured_direction_matches']=all(v['velocity']<0 for v in springs)
 elif not old_live and springs and abs(mid_y(b['presentation'])-mid_y(b['model']))<.1:
  analysis['direction_configuration']='old_animation_settled_requires_zero'
  analysis['configured_direction_matches']=all(abs(v['velocity'])<.001 for v in springs)
 else:analysis['direction_configuration']='inconclusive'
else:analysis['direction_configuration']='presentation_unavailable'
sources=json.loads((out/'sources.json').read_text());assert len(sources)==518
for rel,h in sources.items():assert hashlib.sha256((root/rel).read_bytes()).hexdigest()==h,rel
(out/'analysis.json').write_text(json.dumps(analysis,indent=2)+'\n')
print('PASS actual baseline structure/518 current inputs; dynamic direction result:',analysis)
