#!/usr/bin/env python3
import hashlib,json,sys
from pathlib import Path
import jsonschema
root=Path(sys.argv[1])/"docs/handoff/reference/codex-app-server-schema-0.153.0/v2"
names={"thread/start":"ThreadStartParams","thread/resume":"ThreadResumeParams","turn/start":"TurnStartParams","model/list":"ModelListParams"}
results=[]
for line in Path(sys.argv[2]).read_text().splitlines():
 obj=json.loads(line);p=root/(names[obj['method']]+'.json');raw=p.read_bytes()
 jsonschema.validate(obj['params'],json.loads(raw))
 results.append({'method':obj['method'],'schema':p.name,'schemaSHA256':hashlib.sha256(raw).hexdigest(),'status':'PASS'})
Path(sys.argv[3]).write_text(json.dumps({'fixtures':results,'boundary':'JSON shape only, no transport, permission or CLI semantics'},indent=2)+'\n')
print('Pinned schema:',len(results),'actual outbound params passed')
