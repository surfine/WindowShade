#!/usr/bin/env python3
import argparse,hashlib,json,pathlib,sys
p=argparse.ArgumentParser();p.add_argument('--film',type=pathlib.Path,required=True);p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args()
errors=[]
def issue(code,asset):errors.append({'code':code,'asset':asset})
base=a.film.resolve(); reg=base/'public/footage/capture-registry.json'; manifest=base/'public/footage/manifest.json'
try: records=json.loads(reg.read_text()); flags=json.loads(manifest.read_text())
except Exception as e: print('BLOCKED registry unreadable',type(e).__name__);sys.exit(2)
if set(records)!=set(flags):issue('REGISTRY_SET_MISMATCH','footage')
if len(records)!=17:issue('EXPECTED_17_RECORDS','footage')
for name,row in records.items():
    path=(base/'public/footage'/name).resolve()
    if not path.is_relative_to((base/'public/footage').resolve()):issue('UNSAFE_PATH',name);continue
    if row.get('approved') is not True or flags.get(name) is not True:issue('UNAPPROVED',name)
    if row.get('containsSecrets') is not False or not row.get('reviewer'):issue('NO_PRIVACY_REVIEW',name)
    if not isinstance(row.get('license'),str) or 'pending' in row['license'].lower():issue('NO_LICENSE',name)
    if not path.is_file():issue('MISSING_FILE',name);continue
    if row.get('sha256')!=hashlib.sha256(path.read_bytes()).hexdigest():issue('HASH_MISMATCH',name)
    if row.get('kind')=='video' and (not isinstance(row.get('sourceFrames'),int) or row['sourceFrames']<=0):issue('NO_DURATION',name)
# 人工证据单不是自动审美判断；每项必须指向实际报告文件并锁定hash。
required=['remotion-typecheck','landscape-render','portrait-render','audio-rights','audio-listen','loudness','visual-review','carry-review','qc-review']
evidence=base/'final-evidence.json'
try: facts=json.loads(evidence.read_text())
except Exception: facts={}
for key in required:
    row=facts.get(key,{})
    rel=row.get('path','');file=(base/rel).resolve()
    if row.get('status')!='PASS' or not rel or not file.is_relative_to(base) or not file.is_file():issue('MISSING_FINAL_EVIDENCE',key);continue
    if hashlib.sha256(file.read_bytes()).hexdigest()!=row.get('sha256'):issue('EVIDENCE_HASH_MISMATCH',key)
result={'status':'BLOCKED' if errors else 'READY_FOR_HUMAN_RELEASE_REVIEW','errors':errors,'records':len(records)}
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(result['status'],len(errors),'issues');sys.exit(2 if errors else 0)
