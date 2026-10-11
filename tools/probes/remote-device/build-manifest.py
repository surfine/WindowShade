#!/usr/bin/env python3
"""Bind a probe binary to its actual local compilation inputs. No credential material."""
import hashlib, json, pathlib, re, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[3]
script = root / 'tools/probes/remote-device/run.sh'
out = root / '.build/remote-device-probe/build-manifest.json'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def inputs():
    source = script.read_text().replace('$BASE', 'tools/probes/companion-pairing')
    paths = set(re.findall(r'(?:prototype|tools)/[A-Za-z0-9_./-]+\.(?:swift|c|h)', source))
    paths.update(['tools/probes/remote-device/run.sh', 'tools/probes/remote-device/build-manifest.py',
                  'tools/probes/companion-pairing/WSNativeSRP.h','tools/probes/companion-pairing/module.modulemap'])
    return {p:sha(root/p) for p in sorted(paths)}
if sys.argv[1] == 'begin':
    value = {'sourceSHA256':inputs(), 'baseHEAD':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
             'swift':subprocess.check_output(['xcrun','swiftc','--version'],cwd=root,text=True).strip(), 'status':'building'}
    out.write_text(json.dumps(value,indent=2)+'\n')
elif sys.argv[1] == 'finish':
    value = json.loads(out.read_text()); assert inputs()==value['sourceSHA256'], 'build inputs changed'
    value.update(status='built',binarySHA256=sha(out.parent/'RemoteDeviceProbe'))
    out.write_text(json.dumps(value,indent=2)+'\n')
elif sys.argv[1] == 'check':
    value = json.loads(out.read_text()); assert value['status']=='built'
    assert inputs()==value['sourceSHA256'], 'source changed since build'
    assert sha(out.parent/'RemoteDeviceProbe')==value['binarySHA256'], 'binary changed since build'
    print(json.dumps({'status':'matched','inputFiles':len(value['sourceSHA256']),'binarySHA256':value['binarySHA256']}))
else: raise SystemExit(64)
