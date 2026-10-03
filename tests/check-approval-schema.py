#!/usr/bin/env python3
"""Check actual synthetic response body against the included pinned schema, not a live CLI.

装了 jsonschema 就用它做完整校验；这台机器上没有这个包时，退回到按钉住的 schema 里
真正用到的约束做等价检查（对象、必填 decision、以及 oneOf 的各个分支），并明确写出用了哪种模式。
"""
import hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'tests/fixtures/CommandExecutionRequestApprovalResponse.json'
schema=json.loads(p.read_text())

try:
    import jsonschema
    validate=jsonschema.Draft7Validator(schema).validate
    mode='jsonschema'
except ModuleNotFoundError:
    mode='builtin-constraints'
    decision_schema=schema['definitions']['CommandExecutionApprovalDecision']
    def validate(body):
        if not isinstance(body,dict) or set(schema['required'])-set(body): raise ValueError('missing required decision')
        value=body['decision']
        allowed=set()
        objects=[]
        for branch in decision_schema['oneOf']:
            if 'enum' in branch: allowed.update(branch['enum'])
            elif branch.get('type')=='object': objects.append(branch)
        if isinstance(value,str):
            if value not in allowed: raise ValueError(f'decision {value!r} not in {sorted(allowed)}')
            return
        if isinstance(value,dict):
            for branch in objects:
                if set(branch['required']) <= set(value): return
        raise ValueError('decision does not match any pinned branch')

count=0
for line in (ROOT/'.build/part4-core/approval-accept.ndjson').read_text().splitlines():
    if not line.strip(): continue
    message=json.loads(line)
    if set(message)!={'id','result'}: raise ValueError('unexpected response envelope')
    validate(message['result'])
    if message['result']['decision']!='accept': raise ValueError('this test expects one-time accept only')
    count+=1
if count!=1: raise ValueError('expected the one response emitted by the core test')
print(json.dumps({'result':'PASS','responseBodies':count,'validator':mode,'schemaSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),
    'scope':'synthetic body validation; no CLI, no real approval'},indent=2))
