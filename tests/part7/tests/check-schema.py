#!/usr/bin/env python3
"""Validate actual pipe-outbound frames against the supplied, pinned 0.153.0 schema."""
import argparse,collections,hashlib,json,pathlib
import jsonschema
p=argparse.ArgumentParser();p.add_argument('--repo',type=pathlib.Path,required=True);p.add_argument('--messages',type=pathlib.Path,required=True);p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args()
root=a.repo/'docs/handoff/reference/codex-app-server-schema-0.153.0';schemas={}
for name in ['ClientRequest','ClientNotification','CommandExecutionRequestApprovalResponse']:
    data=(root/(name+'.json')).read_bytes();schemas[name]=(jsonschema.Draft7Validator(json.loads(data)),hashlib.sha256(data).hexdigest())
counts=collections.Counter();failures=[]
for line,text in enumerate(a.messages.read_text().splitlines(),1):
    value=json.loads(text)
    if 'method' in value:
        kind='ClientRequest' if 'id' in value else 'ClientNotification';body=value
    else:kind='CommandExecutionRequestApprovalResponse';body=value.get('result')
    errors=list(schemas[kind][0].iter_errors(body));counts[kind]+=1
    if errors:failures.append({'line':line,'kind':kind,'message':errors[0].message,'path':list(errors[0].path)})
result={'schema_version':'0.153.0','messages_sha256':hashlib.sha256(a.messages.read_bytes()).hexdigest(),'counts':dict(counts),'schema_sha256':{k:v[1] for k,v in schemas.items()},'failures':failures,'meaning':'synthetic backend, real candidate outbound bytes; not live CLI, sandbox or authentication proof'}
a.report.write_text(json.dumps(result,indent=2,ensure_ascii=False));print(json.dumps(result,ensure_ascii=False));raise SystemExit(1 if failures else 0)
