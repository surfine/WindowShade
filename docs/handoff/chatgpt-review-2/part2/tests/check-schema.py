#!/usr/bin/env python3
"""Validate captured synthetic messages against the user's pinned 0.153.0 schemas.
Requires Python jsonschema. Does not connect to any CLI or grant approval.
"""
import argparse,hashlib,json,pathlib
import jsonschema
p=argparse.ArgumentParser();p.add_argument('--schema-dir',required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];schema_root=pathlib.Path(a.schema_dir)
mapping={'initialize':'v1/InitializeParams.json','model/list':'v2/ModelListParams.json','thread/start':'v2/ThreadStartParams.json','turn/start':'v2/TurnStartParams.json','turn/steer':'v2/TurnSteerParams.json','turn/interrupt':'v2/TurnInterruptParams.json'}
results=[]
for line in (root/'validation/codex-outbound.ndjson').read_text().splitlines():
 m=json.loads(line);method=m.get('method')
 if method=='initialized':
  assert m=={'method':'initialized'},'Unexpected initialized notification fields'
  results.append({'method':method,'status':'PASS notification structural assertion; no payload schema'});continue
 if method:
  path=mapping[method];payload=m['params']
 else:
  path=('CommandExecutionRequestApprovalResponse.json' if isinstance(m['id'],int) else 'FileChangeRequestApprovalResponse.json');payload=m['result']
 raw=(schema_root/path).read_bytes();schema=json.loads(raw)
 jsonschema.validators.validator_for(schema)(schema).validate(payload)
 results.append({'method':method or 'approval-decline','schema':path,'sha256':hashlib.sha256(raw).hexdigest(),'status':'PASS payload schema'})
print(json.dumps(results,ensure_ascii=False,indent=2))
