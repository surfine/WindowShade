#!/usr/bin/env python3
import argparse, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument("--candidate",type=Path,required=True)
p.add_argument("--map",type=Path,default=Path(__file__).resolve().parents[1]/"sources/code-map.json")
a=p.parse_args();errors=[];records=json.loads(a.map.read_text())["files"]
for item in records:
 rel=Path(item["path"])
 if rel.is_absolute() or ".." in rel.parts: errors.append("invalid map path");continue
 f=a.candidate/rel
 if not f.is_file() or f.is_symlink(): errors.append(item["path"]+": missing or symlink");continue
 raw=f.read_bytes();lines=raw.decode().splitlines()
 if hashlib.sha256(raw).hexdigest()!=item["sha256"]: errors.append(item["path"]+": hash mismatch")
 if len(lines)!=item["lines"]: errors.append(item["path"]+": line count mismatch")
 for s in item["symbols"]:
  if not 1<=s["line"]<=len(lines) or lines[s["line"]-1].strip()!=s["declaration"]:
   errors.append(item["path"]+": symbol anchor changed")
print(json.dumps({"status":"FAIL" if errors else "PASS","files":len(records),"errors":errors},indent=2))
raise SystemExit(2 if errors else 0)
