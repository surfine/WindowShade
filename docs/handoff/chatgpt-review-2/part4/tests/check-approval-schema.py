#!/usr/bin/env python3
"""Check actual synthetic response body against the included pinned schema, not a live CLI."""
import hashlib, json
from pathlib import Path
import jsonschema
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'reference/CommandExecutionRequestApprovalResponse.json'
validator=jsonschema.Draft7Validator(json.loads(p.read_text()))
count=0
for line in (ROOT/'validation/approval-accept.ndjson').read_text().splitlines():
    if not line.strip(): continue
    message=json.loads(line)
    if set(message)!={'id','result'}: raise ValueError('unexpected response envelope')
    validator.validate(message['result'])
    if message['result']['decision']!='accept': raise ValueError('this test expects one-time accept only')
    count+=1
if count!=1: raise ValueError('expected the one response emitted by the core test')
print(json.dumps({'result':'PASS','responseBodies':count,'schemaSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),
    'scope':'synthetic body validation; no CLI, no real approval'},indent=2))
